open Prelude

type value_error =
  | Unexpected_kind of
      { expected : Kind.t
      ; given : Kind.t
      ; value : Ast.t
      }
  | Unexpected_pair of
      { error : pair_error
      ; value : Ast.t
      ; given : Kind.t
      }
  | Unexpected_list of
      { errors : (int * value_error) Nel.t
      ; value : Ast.t
      ; given : Kind.t
      }

and pair_error =
  | Invalid_fst of value_error
  | Invalid_snd of value_error
  | Invalid_both of value_error * value_error

let pp_record l = Fmt.braces (Fmt.record ~sep:(Fmt.any ";@,") l)

let rec pp_value_error st = function
  | Unexpected_kind { expected; given; value } ->
    pp_record
      Fmt.
        [ field "message" (fun (x, _, _, _) -> x) Dump.string
        ; field "expected" (fun (_, x, _, _) -> x) Kind.pp
        ; field "given" (fun (_, _, x, _) -> x) Kind.pp
        ; field "value" (fun (_, _, _, x) -> x) Ast.pp
        ]
      st
      ("unexpected kind", expected, given, value)
  | Unexpected_pair { error; value; given } ->
    pp_record
      Fmt.
        [ field "message" (fun (x, _, _, _) -> x) Dump.string
        ; field "where" (fun (_, _, _, x) -> x) pp_pair_error
        ; field "given" (fun (_, x, _, _) -> x) Kind.pp
        ; field "value" (fun (_, _, x, _) -> x) Ast.pp
        ]
      st
      ("unexpected pair", given, value, error)
  | Unexpected_list { errors; value; given } ->
    pp_record
      Fmt.
        [ field "message" (fun (x, _, _, _) -> x) Dump.string
        ; field "where" (fun (_, _, _, x) -> x) (Dump.list pp_indexed_error)
        ; field "given" (fun (_, x, _, _) -> x) Kind.pp
        ; field "value" (fun (_, _, x, _) -> x) Ast.pp
        ]
      st
      ("unexpected list", given, value, Nel.to_list errors)

and pp_indexed_error st (index, error) =
  Fmt.pf st "%02d:@,@[<h>%a@]" index pp_value_error error

and pp_pair_error st = function
  | Invalid_fst err ->
    pp_record
      Fmt.[ field "on" fst Dump.string; field "error" snd pp_value_error ]
      st
      ("first", err)
  | Invalid_snd err ->
    pp_record
      Fmt.[ field "on" fst Dump.string; field "error" snd pp_value_error ]
      st
      ("second", err)
  | Invalid_both (errf, errs) ->
    pp_record
      Fmt.
        [ field "on" (fun (x, _, _) -> x) Dump.string
        ; field "first_error" (fun (_, x, _) -> x) pp_value_error
        ; field "second_error" (fun (_, _, x) -> x) pp_value_error
        ]
      st
      ("both", errf, errs)
;;

let pp_checked pp = Fmt.result ~ok:pp ~error:pp_value_error

type 'a checked = ('a, value_error) result
type ('a, 'b) v = 'a -> 'b checked
type 'a t = (Ast.t, 'a) v

module Infix = struct
  let ( <$> ) = Result.map
  let ( $ ) l f x = Result.map f (l x)
  let ( & ) l r x = Result.bind (l x) r
  let ( / ) l r x = Result.fold ~ok:Result.ok ~error:(fun _ -> r x) (l x)
end

module Syntax = struct
  let ( let+ ) x f = Result.map f x
  let ( let* ) = Result.bind

  let ( and+ ) a b =
    match a, b with
    | Ok x, Ok y -> Ok (x, y)
    | Error err, _ | _, Error err -> Error err
  ;;

  let ( and* ) = ( and+ )
end

include Infix
include Syntax

let strim subject = subject |> String.trim |> String.lowercase_ascii

let unexpected_kind expected value =
  let given = Kind.classify value in
  Error (Unexpected_kind { expected; given; value })
;;

let replace_expected_kind new_kind = function
  | Error (Unexpected_kind { given; value; _ }) ->
    Error (Unexpected_kind { expected = new_kind; given; value })
  | value -> value
;;

let unexpected_list value errors =
  let given = Kind.classify value in
  Unexpected_list { value; given; errors = Nel.rev errors }
;;

let unexpected_pair value error =
  let given = Kind.classify value in
  Error (Unexpected_pair { error; given; value })
;;

let null = function
  | Ast.Null -> Ok ()
  | value -> unexpected_kind Kind.Null value
;;

let unit = function
  | Ast.Unit -> Ok ()
  | value -> unexpected_kind Kind.Unit value
;;

let unitish = function
  | Ast.Unit | Ast.Null -> Ok ()
  | value -> unexpected_kind Kind.(Unit || Null) value
;;

let bool ?(strict = false) = function
  | Ast.Bool x -> Ok x
  | Ast.String s as value when not strict ->
    (match strim s with
     | "true" -> Ok true
     | "false" -> Ok false
     | _ -> unexpected_kind Kind.Bool value)
  | value -> unexpected_kind Kind.Bool value
;;

let char ?(strict = false) = function
  | Ast.Char c -> Ok c
  | Ast.String s when (not strict) && Int.equal 1 (String.length s) -> Ok s.[0]
  | value ->
    (* Maybe handle integers as potential chars. *)
    unexpected_kind Kind.Char value
;;

let as_number kind from into equal i value =
  let x = into i in
  let y = from x in
  if not (equal i y) then unexpected_kind kind value else Ok x
;;

let from_string kind from into s value =
  let s = strim s in
  match from s with
  | None -> unexpected_kind kind value
  | Some x ->
    let y = into x in
    if String.equal s y then Ok x else unexpected_kind kind value
;;

let int ?(strict = false) = function
  | Ast.Int i -> Ok i
  | Ast.String s as value when not strict ->
    from_string Kind.Int int_of_string_opt string_of_int s value
  | Ast.Int32 i as value when not strict ->
    as_number Kind.Int Int32.of_int Int32.to_int Int32.equal i value
  | Ast.Int64 i as value when not strict ->
    as_number Kind.Int Int64.of_int Int64.to_int Int64.equal i value
  | Ast.Float i as value when not strict ->
    as_number Kind.Int Float.of_int Float.to_int Float.equal i value
  | value -> unexpected_kind Kind.Int value
;;

let int32 ?(strict = false) = function
  | Ast.Int32 i -> Ok i
  | Ast.Int i when not strict -> Ok (Int32.of_int i)
  | Ast.Int64 i as value when not strict ->
    as_number Kind.Int32 Int64.of_int32 Int64.to_int32 Int64.equal i value
  | Ast.Float i as value when not strict ->
    as_number Kind.Int32 Int32.to_float Int32.of_float Float.equal i value
  | Ast.String s as value when not strict ->
    from_string Kind.Int32 Int32.of_string_opt Int32.to_string s value
  | value -> unexpected_kind Kind.Int32 value
;;

let int64 ?(strict = false) = function
  | Ast.Int64 i -> Ok i
  | Ast.Int i when not strict -> Ok (Int64.of_int i)
  | Ast.Int32 i when not strict -> Ok (Int64.of_int32 i)
  | Ast.Float i as value when not strict ->
    as_number Kind.Int64 Int64.to_float Int64.of_float Float.equal i value
  | Ast.String s as value when not strict ->
    from_string Kind.Int64 Int64.of_string_opt Int64.to_string s value
  | value -> unexpected_kind Kind.Int64 value
;;

let float ?(strict = false) = function
  | Ast.Float f -> Ok f
  | Ast.Int i as value when not strict ->
    as_number Kind.Float int_of_float float_of_int Int.equal i value
  | Ast.Int32 i as value when not strict ->
    as_number Kind.Float Int32.of_float Int32.to_float Int32.equal i value
  | Ast.Int64 i as value when not strict ->
    as_number Kind.Float Int64.of_float Int64.to_float Int64.equal i value
  | Ast.String s as value when not strict ->
    (* Canot rely on round-trip because "3" is, ie, a valid float. *)
    (match float_of_string_opt s with
     | Some x -> Ok x
     | None -> unexpected_kind Kind.Float value)
  | value -> unexpected_kind Kind.Float value
;;

let integer ?(strict = false) subject =
  subject
  |> int64 ~strict
     / (int32 ~strict $ Int64.of_int32)
     / (int ~strict $ Int64.of_int)
  |> replace_expected_kind Kind.(Int || Int32 || Int64)
;;

let number ?(strict = false) subject =
  subject
  |> float ~strict / (integer ~strict $ Int64.to_float)
  |> replace_expected_kind Kind.(Int || Int32 || Int64 || Float)
;;

let string ?(strict = false) = function
  | Ast.String s -> Ok s
  | Ast.Bool b when not strict -> Ok (string_of_bool b)
  | Ast.Char c when not strict -> Ok (String.make 1 c)
  | Ast.Int i when not strict -> Ok (string_of_int i)
  | Ast.Int32 i when not strict -> Ok (Int32.to_string i)
  | Ast.Int64 i when not strict -> Ok (Int64.to_string i)
  | Ast.Float i when not strict -> Ok (Float.to_string i)
  | value -> unexpected_kind Kind.String value
;;

let pair fst snd = function
  | (Ast.Pair (a, b) | Ast.List [ a; b ]) as value ->
    (match fst a, snd b with
     | Ok x, Ok y -> Ok (x, y)
     | Error x, Ok _ -> unexpected_pair value (Invalid_fst x)
     | Ok _, Error x -> unexpected_pair value (Invalid_snd x)
     | Error x, Error y -> unexpected_pair value (Invalid_both (x, y)))
  | value -> unexpected_kind Kind.(Pair (Any, Any)) value
;;

let triple fst snd trd x =
  let rec aux = function
    (* Be more lax on tuple treatement. *)
    | Ast.List [ a; b; c ] -> aux Ast.(lpair a (lpair b c))
    | value -> (pair fst (pair snd trd) $ fun (x, (y, z)) -> x, y, z) value
  in
  aux x
;;

let quad fst snd trd frd x =
  let rec aux = function
    (* Be more lax on tuple treatement. *)
    | Ast.List [ a; b; c; d ] -> aux Ast.(lpair a (lpair b (lpair c d)))
    | value ->
      (pair fst (pair snd (pair trd frd)) $ fun (w, (x, (y, z))) -> w, x, y, z)
        value
  in
  aux x
;;

let list = function
  | Ast.List list -> Ok list
  | value -> unexpected_kind Kind.(List Any) value
;;

let list_of v = function
  | Ast.List list as value ->
    List.rev
    <$> snd
        @@ List.fold_left
             (fun (i, acc) value ->
                let acc =
                  match acc, v value with
                  | Ok xs, Ok x -> Ok (x :: xs)
                  | Error xs, Error x -> Error (Nel.cons (i, x) xs)
                  | Error e, _ -> Error e
                  | _, Error e -> Error (Nel.singleton (i, e))
                in
                i + 1, acc)
             (0, Ok [])
             list
    |> Result.map_error (unexpected_list value)
  | value -> unexpected_kind Kind.(List Any) value
;;

let find_assoc ?(normalize = true) key assoc =
  List.find_map
    (fun (k, v) ->
       let eq =
         if normalize
         then String.equal (strim key) (strim k)
         else String.equal key k
       in
       if eq then Some v else None)
    assoc
;;

let sum ctors expr =
  let kind =
    ctors
    |> List.map (fun (ctor, _) -> Kind.Constr (strim ctor, Any))
    |> Kind.from_list
  in
  let rec aux = function
    | Ast.Constr (ctor, expr) as value ->
      ctors
      |> find_assoc ctor
      |> Option.fold ~none:(unexpected_kind kind value) ~some:(fun validator ->
        validator expr)
    | Pair (String ctor, expr) | List [ String ctor; expr ] ->
      aux (Ast.constr (fun _ -> ctor, expr) ())
    | Record _record ->
      (* TODO: use record validation here. *)
      assert false
    | value -> unexpected_kind kind value
  in
  aux expr
;;

let option some = function
  | Ast.Null -> Ok None
  | value -> Option.some <$> some value
;;

let either left right =
  sum [ "left", left $ Either.left; "right", right $ Either.right ]
;;

let result ok error =
  sum [ "ok", ok $ Result.ok; "error", error $ Result.error ]
;;
