module M = Kohai_model.Transient_log
module L = Kohai_model.Log

let all ?body ?id (module H : Eff.HANDLER) =
  let cwd = Global.ensure_supervision ?body ?id (module H) () in
  let file = Kohai_model.Resolver.transient_logs ~cwd in
  let content = Eff.read_file (module H) file in
  M.from_file_content content
;;

let list ?body ?id (module H : Eff.HANDLER) () =
  let now = Eff.now (module H) in
  now, all ?body ?id (module H) |> M.sort
;;

let get ?body ?id (module H : Eff.HANDLER) index =
  all ?body ?id (module H) |> List.find_opt (M.has_index index)
;;

let store_missing_sector ?body ?id (module H : Eff.HANDLER) sector =
  sector |> Kohai_model.Described_item.make |> Sector.save ?body ?id (module H)
;;

let store_missing_project ?body ?id (module H : Eff.HANDLER) project =
  project
  |> Kohai_model.Described_item.make
  |> Project.save ?body ?id (module H)
;;

let store_missing_data ?body ?id (module H : Eff.HANDLER) ~sector ~project =
  let _ = store_missing_sector ?body ?id (module H) sector
  and () =
    match project with
    | Some project ->
      store_missing_project ?body ?id (module H) project |> ignore
    | None -> ()
  in
  ()
;;

let adding ?body ?id (module H : Eff.HANDLER) add file now index key value =
  let transients =
    all ?body ?id (module H)
    |> List.map (fun log ->
      if M.has_index index log then add ~key ~value log else log)
  in
  let result = M.to_result transients in
  let content = M.dump result in
  let () = Eff.write_file (module H) file content in
  now, result
;;

let removing ?body ?id (module H : Eff.HANDLER) remove file now index key =
  let transients =
    all ?body ?id (module H)
    |> List.map (fun log ->
      if M.has_index index log then remove ~key log else log)
  in
  let result = M.to_result transients in
  let content = M.dump result in
  let () = Eff.write_file (module H) file content in
  now, result
;;

let action_record
      ?body
      ?id
      (module H : Eff.HANDLER)
      file
      now
      date_query
      project
      sector
      label
  =
  let () = store_missing_data ?body ?id (module H) ~sector ~project in
  let transients = all ?body ?id (module H) in
  let start_date = Datetime.Query.resolve now date_query in
  let transient = M.make ~start_date ~project ~sector ~label in
  let result = M.to_result ~inserted:transient transients in
  let content = M.dump result in
  let () = Eff.write_file (module H) file content in
  now, result
;;

let stop_recording_action
      ?body
      ?id
      (module H : Eff.HANDLER)
      file
      now
      index
      duration
  =
  let transients =
    all ?body ?id (module H)
    |> List.map (fun log ->
      if M.has_index index log
      then M.finalize_duration now log duration
      else log)
  in
  let result = M.to_result transients in
  let content = M.dump result in
  let () = Eff.write_file (module H) file content in
  now, result
;;

let rewrite_action
      ?body
      ?id
      (module H : Eff.HANDLER)
      file
      now
      index
      date_query
      project
      sector
      label
  =
  let () = store_missing_data ?body ?id (module H) ~sector ~project in
  let start_date = Datetime.Query.resolve now date_query in
  let patched_log = M.make ~start_date ~project ~sector ~label in
  let transients =
    all ?body ?id (module H)
    |> List.map (fun log -> if M.has_index index log then patched_log else log)
  in
  let result = M.to_result transients in
  let content = M.dump result in
  let () = Eff.write_file (module H) file content in
  now, result
;;

let delete_action ?body ?id (module H : Eff.HANDLER) file now index =
  let transients =
    all ?body ?id (module H)
    |> List.filter (fun log -> not (M.has_index index log))
  in
  let result = M.to_result transients in
  let content = M.dump result in
  let () = Eff.write_file (module H) file content in
  now, result
;;

let add_meta_action ?body ?id (module H : Eff.HANDLER) file now index key value =
  adding ?body ?id (module H) M.add_meta file now index key value
;;

let add_link_action ?body ?id (module H : Eff.HANDLER) file now index key value =
  adding ?body ?id (module H) M.add_link file now index key value
;;

let remove_meta_action ?body ?id (module H : Eff.HANDLER) file now index key =
  removing ?body ?id (module H) M.remove_meta file now index key
;;

let remove_link_action ?body ?id (module H : Eff.HANDLER) file now index key =
  removing ?body ?id (module H) M.remove_link file now index key
;;

let promote_action ?body ?id (module H : Eff.HANDLER) file now cwd index =
  let tl = get ?body ?id (module H) index in
  let log = Option.bind tl (fun x -> L.from_transient_log x) in
  match log with
  | Some log ->
    (* Dump log in the related file. *)
    let () = Log.promote ?body ?id (module H) cwd log in
    (* Remove the current transient log. *)
    delete_action ?body ?id (module H) file now index
  | None ->
    Eff.raise (module H) (Error.no_related_transient_log ?body ?id index)
;;

let action ?body ?id (module H : Eff.HANDLER) operation =
  let cwd = Global.ensure_supervision ?body ?id (module H) () in
  let file = Kohai_model.Resolver.transient_logs ~cwd in
  let now = Eff.now (module H) in
  let apply f = f ?body ?id (module H : Eff.HANDLER) file now in
  match operation with
  | M.Record { date_query; project; sector; label } ->
    apply action_record date_query project sector label
  | M.Stop_recording { index; duration } ->
    apply stop_recording_action index duration
  | M.Rewrite { index; date_query; project; sector; label } ->
    apply rewrite_action index date_query project sector label
  | M.Delete { index } -> apply delete_action index
  | M.Add_meta { index; key; value } -> apply add_meta_action index key value
  | M.Remove_meta { index; key } -> apply remove_meta_action index key
  | M.Add_link { index; key; value } -> apply add_link_action index key value
  | M.Remove_link { index; key } -> apply remove_link_action index key
  | M.Promote { index } -> apply promote_action cwd index
;;
