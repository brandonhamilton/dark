open Prelude

(* Dark *)
module B = BlankOr
module TD = TLIDDict

let toID (db : db) : TLID.t = db.dbTLID

let upsert (m : model) (db : db) : model =
  {m with dbs = TD.insert ~tlid:db.dbTLID ~value:db m.dbs}


let update (m : model) ~(tlid : TLID.t) ~(f : db -> db) : model =
  {m with dbs = TD.updateIfPresent ~tlid ~f m.dbs}


let remove (m : model) (db : db) : model =
  {m with dbs = TD.remove ~tlid:db.dbTLID m.dbs}


let fromList (dbs : db list) : db TLIDDict.t =
  dbs |> List.map ~f:(fun db -> (db.dbTLID, db)) |> TLIDDict.fromList


let blankOrData (db : db) : blankOrData list =
  let cols =
    match db.activeMigration with
    | Some migra ->
        db.cols @ migra.cols
    | None ->
        db.cols
  in
  let colpointers =
    cols
    |> List.map ~f:(fun (lhs, rhs) -> [PDBColName lhs; PDBColType rhs])
    |> List.concat
  in
  PDBName db.dbName :: colpointers


let hasCol (db : db) (name : string) : bool =
  db.cols
  |> List.any ~f:(fun (colname, _) ->
         match colname with Blank _ -> false | F (_, n) -> name = n)


let isLocked (m : model) (tlid : TLID.t) : bool =
  not (StrSet.has ~value:(TLID.toString tlid) m.unlockedDBs)


let isMigrationCol (db : db) (id : ID.t) : bool =
  match db.activeMigration with
  | Some schema ->
      let inCols =
        schema.cols
        |> List.filter ~f:(fun (n, t) -> B.toID n = id || B.toID t = id)
      in
      not (List.isEmpty inCols)
  | None ->
      false


let isMigrationLockReady (m : dbMigration) : bool =
  not
    (FluidExpression.isBlank m.rollforward || FluidExpression.isBlank m.rollback)


let startMigration (tlid : TLID.t) (cols : dbColumn list) : modification =
  let newCols =
    cols |> List.map ~f:(fun (n, t) -> (B.clone identity n, B.clone identity t))
  in
  let rb = B.new_ () in
  let rf = B.new_ () in
  AddOps ([CreateDBMigration (tlid, B.toID rb, B.toID rf, newCols)], FocusSame)


let generateDBName (_ : unit) : string =
  "Db" ^ (() |> Util.random |> string_of_int)
