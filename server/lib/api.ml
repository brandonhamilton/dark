open Core
open Types

open Op

let backfill_id (head : op) (rest : op list) : op list =
  let id = id_of_option head in
  let rest = match id with
    | None -> rest
    | Some id ->
      List.map ~f:(fun op -> match op with
          | (Add_edge (s, -1, p)) -> Add_edge (s, id, p)
          | op -> op)
        rest
  in
  head :: rest


let json2op (json : json) : op =
  match json with
  | `Assoc [optype, args] -> (
    let str field = J.member field args |> J.to_string in
    let int field = J.member field args |> J.to_int in
    let intlist field = args
                        |> J.member field
                        |> J.to_list
                        |> List.map ~f:J.to_int in
    let maybe_id name = match J.member name args with
      | `Int id -> id
      (* When they come in first, they don't have an id, so add one. *)
      | `Null -> Util.create_id ()
      | j -> "IDs must be ints, not '" ^ (Yojson.Basic.to_string j) ^ "'"
             |> Exception.raise in
    let id = maybe_id "id" in
    let loc : (unit -> loc) =
      (fun _ : loc -> { x = int "x"; y = int "y" }) in
    match optype with
    | "add_datastore" -> Add_datastore (str "name", id, loc ())
    | "add_function_call" ->
      Add_fn_call (str "name", id, loc (), intlist "edges")
    | "add_anon" ->
      Add_anon (id, maybe_id "inner_id", loc ())
    | "add_value" -> Add_value (str "value", id, loc ())
    | "update_node_position" -> Update_node_position (int "id", loc ())
    | "add_edge" -> Add_edge (int "src", int "target", str "param")
    | "delete_edge" -> Delete_edge (int "src", int "target", str "param")
    | "delete_node" -> Delete_node (int "id")
    | "clear_edges" -> Clear_edges (int "id")
    | "select_node" -> Select_node (int "id")
    (* TODO: put this into the frontend *)
    | "add_datastore_field" ->

      let (list, tipe) =
        match String.split_on_chars
                (str "tipe") ~on:['['; ']'] with
        | ["["; s; "]"] -> (true, s)
        | [s] -> (false, s)
        | _ -> failwith "other pattern"
      in
      Add_datastore_field (int "id", str "name", tipe, list)
    | _ -> failwith ("not a valid optype: " ^ optype))
  | _ ->
    failwith ("incorrect op structure" ^ (Yojson.Basic.to_string json))


let op2json op : json =
  let str k v = (k, `String v) in
  let int k v = (k, `Int v) in
  let bool k v = (k, `Bool v) in
  let intlist k vs = (k, `List (List.map ~f:(fun i -> `Int i) vs)) in
  let id id = int "id" id in
  let x (loc : loc) = int "x" loc.x in
  let y (loc : loc) = int "y" loc.y in
  let (name, args) = match op with
    | Add_fn_call (name, _id, loc, edges) ->
      "add_function_call",
      [str "name" name; id _id; x loc; y loc; intlist "edges" edges]
    | Add_anon (_id, inner_id, loc) ->
      "add_anon", [id _id; int "inner_id" inner_id; x loc; y loc]
    | Add_datastore (name, _id, loc) ->
      "add_datastore", [str "name" name; id _id; x loc; y loc]
    | Add_value (expr, _id, loc) ->
      "add_value", [str "value" expr; id _id; x loc; y loc]
    (* TODO: deal with is_list *)
    | Add_datastore_field (_id, name, tipe, _) ->
      "add_datastore_field",
      [id _id; str "name" name; str "tipe" tipe; bool "is_list" false]
    | Update_node_position (_id, loc) ->
      "update_node_position", [id _id; x loc; y loc]
    | Select_node (_id) ->
      "select_node", [id _id]
    | Delete_node _id ->
      "delete_node", [id _id]
    | Add_edge (sid, tid, param) ->
      "add_edge", [int "src" sid; int "target" tid; str "param" param]
    | Delete_edge (sid, tid, param) ->
      "delete_edge", [int "src" sid; int "target" tid; str "param" param]
    | Clear_edges _id -> "clear_edges", [id _id]
  in `Assoc [name, `Assoc args]
