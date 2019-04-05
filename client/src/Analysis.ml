open Tc
open Prelude
open Types

(* Tea *)
module Cmd = Tea.Cmd

(* Dark *)
module B = Blank
module P = Pointer
module RT = Runtime
module TL = Toplevel

(* "current" in this indicates that it uses the cursor to pick the right inputValue *)

let defaultResults : analysisResults = {liveValues = StrDict.empty}

(* ---------------------- *)
(* Analyses *)
(* ---------------------- *)

let getTraces (m : model) (tlid : tlid) : trace list =
  StrDict.get ~key:(deTLID tlid) m.traces
  |> Option.withDefault
       ~default:
         [ ( BsUuid.Uuid.V5.create
               ~name:(deTLID tlid)
               ~namespace:(`Uuid "00000000-0000-0000-0000-000000000000")
             |> BsUuid.Uuid.V5.toString
           , None ) ]


let getTrace (m : model) (tlid : tlid) (traceID : traceID) : trace option =
  getTraces m tlid |> List.find ~f:(fun (id, _) -> id = traceID)


let getAnalysisResults (m : model) (traceID : traceID) : analysisResults option
    =
  (* only handlers have analysis results, but lots of stuff expect this *)
  (* data to exist. It may be better to not do that, but this is fine *)
  (* for now. *)
  StrDict.get ~key:traceID m.analyses


let record (old : analyses) (id : traceID) (result : analysisResults) :
    analyses =
  StrDict.insert ~key:id ~value:result old


let replaceFunctionResult
    (m : model)
    (tlid : tlid)
    (traceID : traceID)
    (callerID : id)
    (fnName : string)
    (hash : dvalArgsHash)
    (dval : dval) : model =
  let newResult = {fnName; callerID; argHash = hash; value = dval} in
  let traces =
    m.traces
    |> StrDict.update ~key:(deTLID tlid) ~f:(fun ml ->
           ml
           |> Option.withDefault
                ~default:
                  [ ( traceID
                    , Some
                        { input = StrDict.empty
                        ; timestamp = ""
                        ; functionResults = [newResult] } ) ]
           |> List.map ~f:(fun ((tid, tdata) as t) ->
                  if tid = traceID
                  then
                    ( tid
                    , Option.map tdata ~f:(fun tdata ->
                          { tdata with
                            functionResults =
                              newResult :: tdata.functionResults } ) )
                  else t )
           |> fun x -> Some x )
  in
  {m with traces}


let getArguments
    (m : model) (tl : toplevel) (traceID : traceID) (callerID : id) :
    dval list option =
  let caller = TL.find tl callerID in
  let threadPrevious =
    match TL.rootOf tl with
    | Some (PExpr expr) ->
        Option.toList (AST.threadPrevious callerID expr)
    | _ ->
        []
  in
  let args =
    match caller with
    | Some (PExpr (F (_, FnCall (_, args, _)))) ->
        threadPrevious @ args
    | _ ->
        []
  in
  let argIDs = List.map ~f:B.toID args in
  let analyses = StrDict.get ~key:traceID m.analyses in
  let dvals =
    match analyses with
    | Some analyses_ ->
        List.filterMap
          ~f:(fun id -> StrDict.get ~key:(deID id) analyses_.liveValues)
          argIDs
    | None ->
        []
  in
  if List.length dvals = List.length argIDs then Some dvals else None


(* ---------------------- *)
(* Cursors *)
(* ---------------------- *)

let cursor' (tlCursors : tlCursors) (traces : trace list) (tlid : tlid) :
    traceID option =
  (* We briefly do analysis on a toplevel which does not have an *)
  (* analysis available, so be careful here. *)
  match StrDict.get ~key:(deTLID tlid) tlCursors with
  | Some c ->
      Some c
  | None ->
      (* if we don't have it, pick the first trace *)
      List.head traces |> Option.map ~f:Tuple2.first


let cursor (m : model) (tlid : tlid) : traceID option =
  let traces = getTraces m tlid in
  cursor' m.tlCursors traces tlid


let setCursor (m : model) (tlid : tlid) (traceID : traceID) : model =
  let newCursors =
    StrDict.insert ~key:(deTLID tlid) ~value:traceID m.tlCursors
  in
  {m with tlCursors = newCursors}


(* ---------------------- *)
(* Analyses on current *)
(* ---------------------- *)
let getCurrentTrace (m : model) (tlid : tlid) : trace option =
  getTraces m tlid
  |> List.find ~f:(fun (traceID, _) -> cursor m tlid = Some traceID)


let getCurrentAnalysisResults (m : model) (tlid : tlid) : analysisResults =
  cursor m tlid
  |> Option.andThen ~f:(getAnalysisResults m)
  |> Option.withDefault ~default:defaultResults


let getCurrentLiveValuesDict (m : model) (tlid : tlid) : lvDict =
  getCurrentAnalysisResults m tlid |> fun x -> x.liveValues


let getCurrentLiveValue (m : model) (tlid : tlid) (ID id : id) : dval option =
  tlid |> getCurrentLiveValuesDict m |> StrDict.get ~key:id


let getCurrentTipeOf (m : model) (tlid : tlid) (id : id) : tipe option =
  match getCurrentLiveValue m tlid id with
  | None ->
      None
  | Some dv ->
      Some (RT.typeOf dv)


(* TODO: copied from Libexecution/http.ml *)
let route_variables (route : string) : string list =
  let split_uri_path (path : string) : string list =
    let subs = String.split ~on:"/" path in
    List.filter ~f:(fun x -> String.length x > 0) subs
  in
  route
  |> split_uri_path
  |> List.filter ~f:(String.startsWith ~prefix:":")
  |> List.map ~f:(String.dropLeft ~count:1 (* ":" *))


let getCurrentAvailableVarnames (m : model) (tl : toplevel) (ID id : id) :
    varName list =
  (* TODO: Calling out is so slow that calculating on the fly is faster. But we
   * can also cache this so that's it's not in the display hot-path. *)
  let varsFor ast =
    ast
    |> AST.variablesIn
    |> StrDict.get ~key:id
    |> Option.withDefault ~default:[]
  in
  let dbs = TL.allDBNames m.toplevels in
  match tl.data with
  | TLHandler h ->
      let extras =
        match h.spec.module_ with
        | F (_, m) when String.toLower m = "http" ->
            let fromRoute =
              h.spec.name
              |> Blank.toMaybe
              |> Option.map ~f:route_variables
              |> Option.withDefault ~default:[]
            in
            ["request"] @ fromRoute
        | F (_, m) when String.toLower m = "cron" ->
            []
        | F (_, _) ->
            ["event"]
        | _ ->
            ["request"; "event"]
      in
      varsFor h.ast @ dbs @ extras
  | TLFunc fn ->
      let params =
        fn.ufMetadata.ufmParameters
        |> List.filterMap ~f:(fun p -> Blank.toMaybe p.ufpName)
      in
      varsFor fn.ufAST @ dbs @ params
  | TLDB _ | TLTipe _ ->
      []


(* ---------------------- *)
(* Communication with server *)
(* ---------------------- *)
module ReceiveAnalysis = struct
  let decode : (Js.Json.t, performAnalysisResult) Tea.Json.Decoder.t =
    let open Tea.Json.Decoder in
    map
      (fun msg -> msg)
      (field "detail" (Decoder (fun json -> Tea_result.Ok (Obj.magic json))))


  let listen ~key tagger =
    Native.registerGlobal "receiveAnalysis" key tagger decode
end

module ReceiveTraces = struct
  let decode : (Js.Json.t, traceFetchResult) Tea.Json.Decoder.t =
    let open Tea.Json.Decoder in
    map
      (fun msg -> msg)
      (field "detail" (Decoder (fun json -> Tea_result.Ok (Obj.magic json))))


  let listen ~key tagger =
    Native.registerGlobal "receiveTraces" key tagger decode
end

module NewTracePush = struct
  let decode =
    let open Tea.Json.Decoder in
    let open Native.Decoder in
    let traceID = map (fun id -> (id : traceID)) string in
    let tlids = list (map (fun id -> TLID id) wireIdentifier) in
    field "detail" (pair traceID tlids)


  let listen ~key tagger =
    Native.registerGlobal "newTracePush" key tagger decode
end

module New404Push = struct
  let decode =
    let open Tea.Json.Decoder in
    field "detail" (Decoders.wrapDecoder Decoders.fof)


  let listen ~key tagger = Native.registerGlobal "new404Push" key tagger decode
end

(* Request analysis *)

module RequestAnalysis = struct
  external send : performAnalysisParams -> unit = "requestAnalysis"
    [@@bs.val] [@@bs.scope "window", "Dark", "analysis"]
end

module RequestTraces = struct
  external send : traceFetchContext * getTraceDataRPCParams -> unit = "fetch"
    [@@bs.val] [@@bs.scope "window", "Dark", "traceFetcher"]
end

external origin : string = "origin"
  [@@bs.val] [@@bs.scope "window", "location"]

external prefix : string = "testcafeInjectedPrefix"
  [@@bs.val] [@@bs.scope "window"]

let contextFromModel (m : model) : traceFetchContext =
  {canvasName = m.canvasName; csrfToken = m.csrfToken; origin; prefix}


let requestTrace ?(force = false) m tlid traceID : model * msg Cmd.t =
  let should =
    (* DBs + Types dont have traces *)
    TL.get m tlid
    |> Option.map ~f:(fun tl -> not (TL.isDB tl || TL.isUserTipe tl))
    |> Option.withDefault ~default:false
  in
  if should
  then
    Sync.attempt
      ~force
      ~key:("tracefetch-" ^ traceID)
      m
      (Tea_cmd.call (fun _ ->
           RequestTraces.send
             (contextFromModel m, {gtdrpTlid = tlid; gtdrpTraceID = traceID})
       ))
  else (m, Cmd.none)


let requestAnalysis m tlid traceID : msg Cmd.t =
  let dbs = TL.dbs m.toplevels in
  let userFns = m.userFunctions in
  let userTipes = m.userTipes in
  let trace = getTrace m tlid traceID in
  let tl = TL.getTL m tlid in
  match (tl.data, trace) with
  | TLHandler h, Some (_, Some traceData) ->
      Tea_cmd.call (fun _ ->
          RequestAnalysis.send
            (AnalyzeHandler
               {handler = h; traceID; traceData; dbs; userFns; userTipes}) )
  | TLFunc f, Some (_, Some traceData) ->
      Tea_cmd.call (fun _ ->
          RequestAnalysis.send
            (AnalyzeFunction
               {func = f; traceID; traceData; dbs; userFns; userTipes}) )
  | _ ->
      Cmd.none


let analyzeFocused (m : model) : model * msg Cmd.t =
  match tlidOf m.cursorState with
  | Some tlid ->
    ( match getCurrentTrace m tlid with
    | Some (traceID, None) ->
        (* Fetch the trace data, if missing *)
        requestTrace m tlid traceID
    | Some (traceID, Some _) ->
        (* Run the analysis, if missing *)
        (m, requestAnalysis m tlid traceID)
    | None ->
        (m, Cmd.none) )
  | None ->
      (m, Cmd.none)
