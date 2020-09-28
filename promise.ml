open Js_of_ocaml

type +'a t = < > Js.t

type error = Js_of_ocaml.Js.Unsafe.any

let promise_constr = Js.Unsafe.global##._Promise

let indirect_promise_constr = Js.Unsafe.global##._IndirectPromise

let wrap (value : 'a) : 'a = indirect_promise_constr##wrap value

let unwrap (value : 'a) : 'a = indirect_promise_constr##unwrap value

let make (f : resolve:('a -> unit) -> reject:('e -> unit) -> unit) : 'a t =
  let f_safe resolve reject =
    let resolve_safe value = resolve (wrap value) in
    f ~resolve:resolve_safe ~reject
  in
  new%js promise_constr (Js.wrap_callback f_safe)

let resolve (value : 'a) : 'a t = promise_constr##resolve (wrap value)

let reject (reason : 'e) : 'a t = promise_constr##reject reason

let catch ~(rejected : error -> 'a t) (promise : 'a t) : 'a t =
  (Js.Unsafe.coerce promise)##catch (Js.wrap_callback rejected)

let then_ ~(fulfilled : 'a -> 'b t) ?(rejected : (error -> 'b t) option)
    (promise : 'a t) : 'b t =
  let fulfilled_safe value = fulfilled (unwrap value) in
  match rejected with
  | None          ->
    (Js.Unsafe.coerce promise)##then_ (Js.wrap_callback fulfilled_safe)
  | Some rejected ->
    (Js.Unsafe.coerce promise)##then_
      (Js.wrap_callback fulfilled_safe)
      (Js.wrap_callback rejected)

let finally ~(f : unit -> unit) (promise : 'a t) : 'a t =
  (Js.Unsafe.coerce promise)##finally (Js.wrap_callback f)

let all (promises : 'a t array) : 'a array t =
  promise_constr##all (Js.array promises)
  |> then_ ~fulfilled:(fun value ->
         resolve (Array.map unwrap (Js.to_array value)))

let all2 ((p1 : 'a t), (p2 : 'b t)) : ('a * 'b) t =
  promise_constr##all (Js.array [| p1; p2 |])
  |> then_ ~fulfilled:(fun value ->
         let arr = Js.to_array value in
         resolve (unwrap arr.(0), unwrap arr.(1)))

let all3 ((p1 : 'a t), (p2 : 'b t), (p3 : 'c t)) : ('a * 'b * 'c) t =
  promise_constr##all (Js.array [| p1; p2; p3 |])
  |> then_ ~fulfilled:(fun value ->
         let arr = Js.to_array value in
         resolve (unwrap arr.(0), unwrap arr.(1), unwrap arr.(2)))

let all_list (promises : 'a t list) : 'a list t =
  all (Array.of_list promises)
  |> then_ ~fulfilled:(fun value -> resolve (Array.to_list value))

let race (promises : 'a t array) : 'a t =
  promise_constr##race (Js.array promises)

let race_list (promises : 'a t list) : 'a t = race (Array.of_list promises)

let return = resolve

let map f promise = then_ ~fulfilled:(fun value -> return (f value)) promise

let bind f promise = then_ ~fulfilled:f promise

module Syntax = struct
  let ( >>| ) x f = map f x

  let ( >>= ) x f = bind f x

  let ( let+ ) x f = map f x

  let ( let* ) x f = bind f x
end

module Array = struct
  let find_map (f : 'a -> 'b option t) (arr : 'a array) : 'b option t =
    let arr = all (Array.map f arr) in
    let find arr =
      match List.find_opt Option.is_some (Array.to_list arr) with
      | None               -> None
      | Some (Some _ as x) -> x
      | Some None          -> assert false
    in
    map find arr

  let filter_map (f : 'a -> 'b option t) (arr : 'a array) : 'b array t =
    let open Syntax in
    let+ arr = all (Array.map f arr) in
    let filter_map = List.filter_map (fun x -> x) in
    Array.of_list (filter_map (Array.to_list arr))
end

module List = struct
  let find_map (f : 'a -> 'b option t) (xs : 'a list) : 'b list t =
    let arr = all_list (List.map f xs) in
    let find xs =
      match List.find_opt Option.is_some xs with
      | None               -> None
      | Some (Some _ as x) -> x
      | Some None          -> assert false
    in
    map find arr

  let filter_map (f : 'a -> 'b option t) (xs : 'a list) : 'b list t =
    let open Syntax in
    let+ xs = all_list (List.map f xs) in
    List.filter_map (fun x -> x) xs
end

module Option = struct
  let iter f =
    bind @@ function
    | Some x -> return (f x : unit)
    | None   -> return ()

  let map f =
    bind @@ function
    | Some x -> return (Some (f x))
    | None   -> return None

  let bind f =
    bind @@ function
    | Some x -> f x
    | None   -> return None

  let return x = return (Some x)

  module Syntax = struct
    let ( >>| ) x f = map f x

    let ( >>= ) x f = bind f x

    let ( let+ ) x f = map f x

    let ( let* ) x f = bind f x
  end
end

module Result = struct
  let from_catch promise =
    let fulfilled value = return (Ok value) in
    let rejected reason = return (Error reason) in
    promise |> then_ ~fulfilled ~rejected

  let iter ?(ok = ignore) ?(error = ignore) =
    bind @@ function
    | Ok o    -> return (ok o)
    | Error e -> return (error e)

  let map f =
    bind @@ function
    | Ok o    -> return (Ok (f o))
    | Error e -> return (Error e)

  let bind f =
    bind @@ function
    | Ok o    -> f o
    | Error e -> return (Error e)

  let return x = return (Ok x)

  module Syntax = struct
    let ( >>| ) x f = map f x

    let ( >>= ) x f = bind f x

    let ( let+ ) x f = map f x

    let ( let* ) x f = bind f x
  end
end

let t_to_js (to_js : 'a -> Ojs.t) (promise : 'a t) : Ojs.t =
  Obj.magic (map to_js promise)

let t_of_js (of_js : Ojs.t -> 'a) (promise : Ojs.t) : 'a t =
  map of_js (Obj.magic promise : Ojs.t t)

type void = unit t

let void_to_js = t_to_js (fun () -> Ojs.variable "undefined")

let void_of_js = t_of_js (fun (_ : Ojs.t) -> ())

let error_to_js : error -> Ojs.t = Obj.magic

let error_of_js : Ojs.t -> error = Obj.magic
