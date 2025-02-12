(** The supervised directory is where log artifacts are stored. *)

(** Defines a new supervised directory. *)
val set
  :  ?body:string
  -> ?id:int
  -> (module Sigs.EFFECT_HANDLER)
  -> Path.t
  -> unit

(** Return the supervised directory for the current session. *)
val get : ?id:int -> (module Sigs.EFFECT_HANDLER) -> unit -> Path.t option

(** Return [true] if a path is valid for supervision, [false]
    otherwise. *)
val is_valid : ?id:int -> (module Sigs.EFFECT_HANDLER) -> Path.t -> bool
