let set ?body ?id (module H : Eff.HANDLER) path =
  let path = Global.check_supervised_path ?body ?id (module H) path in
  Eff.set_supervised_directory (module H) (Some path)
;;

let get ?id:_ (module H : Eff.HANDLER) () =
  Eff.get_supervised_directory (module H)
;;

let is_valid ?id:_ (module H : Eff.HANDLER) path =
  Path.is_absolute path && Eff.is_dir (module H) path
;;
