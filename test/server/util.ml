open Kohai_core

let request_input ?(id = 1) ?params meth =
  Format.asprintf
    {j|{"jsonrpc": "2.0", "method": "%s", "id": %d%s}|j}
    meth
    id
    (match params with
     | None -> ""
     | Some x -> Format.asprintf {|, "params": %s|} x)
;;

let request_dump = function
  | Ok value -> Fmt.str "%a" Rensai.Ast.pp value
  | Error error -> error |> Error.to_rensai |> Fmt.str "%a" Rensai.Ast.pp
;;

let dump_result ?(should_fail = false) result =
  match result with
  | Ok result when not should_fail ->
    result |> Format.asprintf "[DONE]: %a" Rensai.Lang.pp
  | Ok result -> result |> Format.asprintf "[FIXME]: %a" Rensai.Lang.pp
  | Error err when should_fail ->
    err |> Error.to_rensai |> Format.asprintf "[DONE]: %a" Rensai.Lang.pp
  | Error err ->
    err |> Error.to_rensai |> Format.asprintf "[FIXME]: %a" Rensai.Lang.pp
;;

let print_result ?should_fail result =
  result |> dump_result ?should_fail |> print_endline
;;

let request ~id ?params meth =
  let i = !id in
  let () = incr id in
  request_input ~id:i ?params meth
;;

let step (module H : Kohai_core.Eff.HANDLER) ?should_fail ~id callback =
  let req = callback (module H : Kohai_core.Eff.HANDLER) ~id () in
  print_result ?should_fail req
;;

let call (module H : Kohai_core.Eff.HANDLER) ~id ?params meth =
  meth
  |> request
       ~id
       ?params:
         (Option.map
            (fun x -> x |> Rensai.Json.to_yojson |> Yojson.Safe.to_string)
            params)
  |> Kohai_server.Jsonrpc.run (module H) ~services:Kohai_server.Services.all
;;

let call_supervise (module H : Kohai_core.Eff.HANDLER) ~id ~path () =
  let params = Rensai.Ast.string path in
  "kohai/supervision/set" |> call (module H) ~id ~params
;;

let call_supervise_get (module H : Kohai_core.Eff.HANDLER) ~id () =
  "kohai/supervision/get" |> call (module H) ~id
;;

let call_state_get (module H : Kohai_core.Eff.HANDLER) ~id () =
  "kohai/state/get" |> call (module H) ~id
;;

let call_state_get_for_sector (module H : Kohai_core.Eff.HANDLER) ~id ~sector ()
  =
  let params = Rensai.Ast.string sector in
  "kohai/state/get/sector" |> call (module H) ~id ~params
;;

let call_state_get_for_project
      (module H : Kohai_core.Eff.HANDLER)
      ~id
      ~project
      ()
  =
  let params = Rensai.Ast.string project in
  "kohai/state/get/project" |> call (module H) ~id ~params
;;

let call_sector_list (module H : Kohai_core.Eff.HANDLER) ~id () =
  "kohai/sector/list" |> call (module H) ~id
;;

let call_project_list (module H : Kohai_core.Eff.HANDLER) ~id () =
  "kohai/project/list" |> call (module H) ~id
;;

let call_sector_save (module H : Kohai_core.Eff.HANDLER) ~id ~name ?desc () =
  let params =
    let open Rensai.Ast in
    record [ "name", string name; "description", option string desc ]
  in
  "kohai/sector/save" |> call (module H) ~id ~params
;;

let call_project_save (module H : Kohai_core.Eff.HANDLER) ~id ~name ?desc () =
  let params =
    let open Rensai.Ast in
    record [ "name", string name; "description", option string desc ]
  in
  "kohai/project/save" |> call (module H) ~id ~params
;;

let call_project_delete (module H : Kohai_core.Eff.HANDLER) ~id ~name () =
  let params = Rensai.Ast.string name in
  "kohai/project/delete" |> call (module H) ~id ~params
;;

let call_sector_delete (module H : Kohai_core.Eff.HANDLER) ~id ~name () =
  let params = Rensai.Ast.string name in
  "kohai/sector/delete" |> call (module H) ~id ~params
;;

let call_transient_log_list (module H : Kohai_core.Eff.HANDLER) ~id () =
  "kohai/transient-log/list" |> call (module H) ~id
;;

let call_transient_log_record
      (module H : Kohai_core.Eff.HANDLER)
      ~id
      ?date_query
      ?project
      ~sector
      ~label
      ()
  =
  let params =
    let open Rensai.Ast in
    sum
      (fun () ->
         ( "record"
         , record
             [ "date_query", option Datetime.Query.to_rensai date_query
             ; "project", option string project
             ; "sector", string sector
             ; "label", string label
             ] ))
      ()
  in
  "kohai/transient-log/action" |> call (module H) ~id ~params
;;

let call_transient_log_stop_recording
      (module H : Kohai_core.Eff.HANDLER)
      ~id
      ~index
      ?duration
      ()
  =
  let params =
    let open Rensai.Ast in
    sum
      (fun () ->
         ( "stop_recording"
         , record [ "index", int index; "duration", option int duration ] ))
      ()
  in
  "kohai/transient-log/action" |> call (module H) ~id ~params
;;

let call_transient_log_rewrite
      (module H : Kohai_core.Eff.HANDLER)
      ~id
      ~index
      ?date_query
      ?project
      ~sector
      ~label
      ()
  =
  let params =
    let open Rensai.Ast in
    sum
      (fun () ->
         ( "rewrite"
         , record
             [ "index", int index
             ; "date_query", option Datetime.Query.to_rensai date_query
             ; "project", option string project
             ; "sector", string sector
             ; "label", string label
             ] ))
      ()
  in
  "kohai/transient-log/action" |> call (module H) ~id ~params
;;

let call_transient_log_delete (module H : Kohai_core.Eff.HANDLER) ~id ~index () =
  let params =
    let open Rensai.Ast in
    sum (fun () -> "delete", record [ "index", int index ]) ()
  in
  "kohai/transient-log/action" |> call (module H) ~id ~params
;;

let call_transient_log_promote (module H : Kohai_core.Eff.HANDLER) ~id ~index ()
  =
  let params =
    let open Rensai.Ast in
    sum (fun () -> "promote", record [ "index", int index ]) ()
  in
  "kohai/transient-log/action" |> call (module H) ~id ~params
;;

let call_transient_log_add_meta
      (module H : Kohai_core.Eff.HANDLER)
      ~id
      ~index
      ~key
      ~value
      ()
  =
  let params =
    let open Rensai.Ast in
    sum
      (fun () ->
         ( "add_meta"
         , record
             [ "index", int index; "key", string key; "value", string value ] ))
      ()
  in
  "kohai/transient-log/action" |> call (module H) ~id ~params
;;

let call_transient_log_add_link
      (module H : Kohai_core.Eff.HANDLER)
      ~id
      ~index
      ~key
      ~value
      ()
  =
  let params =
    let open Rensai.Ast in
    sum
      (fun () ->
         ( "add_link"
         , record
             [ "index", int index; "key", string key; "value", string value ] ))
      ()
  in
  "kohai/transient-log/action" |> call (module H) ~id ~params
;;

let call_transient_log_remove_meta
      (module H : Kohai_core.Eff.HANDLER)
      ~id
      ~index
      ~key
      ()
  =
  let params =
    let open Rensai.Ast in
    sum
      (fun () ->
         "remove_meta", record [ "index", int index; "key", string key ])
      ()
  in
  "kohai/transient-log/action" |> call (module H) ~id ~params
;;

let call_transient_log_remove_link
      (module H : Kohai_core.Eff.HANDLER)
      ~id
      ~index
      ~key
      ()
  =
  let params =
    let open Rensai.Ast in
    sum
      (fun () ->
         "remove_link", record [ "index", int index; "key", string key ])
      ()
  in
  "kohai/transient-log/action" |> call (module H) ~id ~params
;;

let call_log_last (module H : Kohai_core.Eff.HANDLER) ~id () =
  "kohai/log/last" |> call (module H) ~id
;;

let call_log_last_for_sector (module H : Kohai_core.Eff.HANDLER) ~id ~sector () =
  let params = Rensai.Ast.string sector in
  "kohai/log/last/sector" |> call (module H) ~id ~params
;;

let call_log_last_for_project
      (module H : Kohai_core.Eff.HANDLER)
      ~id
      ~project
      ()
  =
  let params = Rensai.Ast.string project in
  "kohai/log/last/project" |> call (module H) ~id ~params
;;

let call_log_unpromote (module H : Kohai_core.Eff.HANDLER) ~id ~uuid () =
  let params = Rensai.Ast.string uuid in
  "kohai/log/unpromote" |> call (module H) ~id ~params
;;
