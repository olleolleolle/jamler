module GenIQHandler = Jamler_gen_iq_handler
module SM = Jamler_sm
module Hooks = Jamler_hooks
module Config = Jamler_config
module Auth = Jamler_auth

module ModPrivateSQL :
sig
  include Gen_mod.Module
end
  =
struct
  let name = "mod_private_sql"
  let _src = Jamler_log.new_src name

  let rec get_data_rec luser lserver els' res =
    match els' with
    | [] ->
       List.rev res
    | (`XmlElement (_name, attrs, _)) as el :: els -> (
      let lxmlns = Xml.get_attr_s "xmlns" attrs in
      let username = (luser : Jlib.nodepreped :> string) in
      let query =
	[%sql {|
	       select @(data)s from private_storage
               where username=%(username)s and
               namespace=%(lxmlns)s
	       |}]
      in
      let private_data = Sql.query lserver query in (
	  match private_data with
	  | [data] -> (
	    try
	      let newel = Xml.parse_element data in
	      get_data_rec luser lserver els
		((newel :> Xml.element_cdata) :: res)
	    with
	    | _ ->
	       get_data_rec luser lserver els res
	  )
	  | _ ->
	     get_data_rec luser lserver els (el :: res)
    ))
    | _ :: els ->
       get_data_rec luser lserver els res

  let set_data luser _lserver el =
    match el with
    | `XmlElement (_name, attrs, _els) -> (
      match Xml.get_attr_s "xmlns" attrs with
      | "" ->
	 ()
      | xmlns ->
	 let username = (luser : Jlib.nodepreped :> string) in
	 let sdata = Xml.element_to_string el in
	 let insert_private_data =
	   [%sql {|
		  insert into private_storage(username, namespace, data)
		  values (%(username)s, %(xmlns)s, %(sdata)s)
		  |}]
	 in
	 let update_private_data =
	   [%sql {|
		  update private_storage
		  set data = %(sdata)s
		  where username = %(username)s and
		  namespace = %(xmlns)s
		  |}]
	 in
	 Sql.update_t insert_private_data update_private_data;
	 ()
    )
    | _ ->
       ()

  let get_data luser lserver els =
    get_data_rec luser lserver els []

  let process_sm_iq from _to' iq = 
    let luser = from.Jlib.luser in
    let lserver = from.Jlib.lserver in
    match List.mem lserver (Config.myhosts ()) with
    | true -> (
      match iq.Jlib.iq_type with
      | `Set (`XmlElement (name, attrs, els)) ->
         Sql.transaction lserver
	   (fun() ->
	     List.iter
	       (fun el -> set_data luser lserver el) els);
	 `IQ {iq with
	     Jlib.iq_type =
	       `Result
		 (Some (`XmlElement (name, attrs, [])))}
      | `Get subel ->
	 let `XmlElement (name, attrs, els) = subel in
	 try
	   let res_els = get_data luser lserver els in
	   `IQ {iq with
	       Jlib.iq_type =
		 `Result
		   (Some (`XmlElement (name, attrs, res_els)))}
	 with
	 | _ ->
	    `IQ {iq with
		Jlib.iq_type =
		  `Error (Jlib.err_internal_server_error,
			  Some subel)})
    | false -> (
      match iq.Jlib.iq_type with
      | `Set subel
      | `Get subel ->
	 `IQ {iq with
	     Jlib.iq_type =
	       `Error (Jlib.err_not_allowed, Some subel)})

  let remove_user (luser, lserver) =
    let username = (luser : Jlib.nodepreped :> string) in
    let delete_private_storage =
      [%sql {|
	     delete from private_storage
	     where username=%(username)s
             |}]
    in
    let _ = Sql.query lserver delete_private_storage in
    Hooks.OK

  let start host =
    Mod_disco.register_feature host [%xmlns "PRIVATE"];
    [Gen_mod.hook Auth.remove_user host remove_user 50;
     Gen_mod.iq_handler `SM host [%xmlns "PRIVATE"] process_sm_iq ();
    ]

  let stop host =
    Mod_disco.unregister_feature host [%xmlns "PRIVATE"];
    ()

end

let () = Gen_mod.register_mod (module ModPrivateSQL : Gen_mod.Module)
