let src = Jamler_log.new_src "hooks"

let sort_hooks hs =
  let hcompare ((s1 : int), _) (s2, _) = compare s1 s2 in
    List.sort hcompare hs

type result =
  | Stop
  | OK

type 'a hook = (Jlib.namepreped, (int * ('a -> result)) list) Hashtbl.t

let create () = Hashtbl.create 1

let add hook host f seq =
  let h =
    try
      Hashtbl.find hook host
    with
      | Not_found -> []
  in
  let h = sort_hooks ((seq, f) :: h) in
    Hashtbl.replace hook host h

let run hook host x =
  let rec aux x =
    function
      | (_, f) :: h ->
	  (try
	     match f x with
	       | OK -> aux x h
	       | Stop -> ()
	   with
	     | exn ->
                Logs.err ~src
	          (fun m ->
                    m "exception running hook: %a"
                      Jamler_log.pp_exn exn);
		aux x h
	  )
      | [] -> ()
  in
    try
      let h = Hashtbl.find hook host in
	aux x h
    with
      | Not_found -> ()

let delete hook host f seq =
  try
    let h = Hashtbl.find hook host in
    let h =
      List.filter
	(fun (seq', f') ->
	   not (seq = seq' && f == f')
	) h
    in
      Hashtbl.replace hook host h
  with
    | Not_found -> ()


type ('a, 'b) fold_hook =
    (Jlib.namepreped, (int * ('b -> 'a -> result * 'b)) list) Hashtbl.t

let create_fold () = Hashtbl.create 1

let add_fold = add

let run_fold hook host v x =
  let rec aux v x =
    function
    | (_, f) :: h ->
       (try
	  match f v x with
	  | (OK, v) -> aux v x h
	  | (Stop, v) -> v
	with
	| exn ->
           Logs.err ~src
	     (fun m ->
               m "exception running hook: %a"
                 Jamler_log.pp_exn exn);
	   aux v x h
       )
    | [] -> v
  in
  try
    let h = Hashtbl.find hook host in
    aux v x h
  with
  | Not_found -> v

let delete_fold = delete
