let myhosts () =
  List.map Jlib.nameprep_exn ["localhost"; "e.localhost"; "hoi.jabber.ru"] (* TODO *)

let auth_modules _host =
  ["sql"]

let modules _host =
  [("mod_roster_sql", [])]

