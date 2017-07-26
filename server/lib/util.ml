open Core

let readfile ?(default="") f : string =
  let flags = [Unix.O_RDONLY; Unix.O_CREAT] in
  let file = Unix.openfile f ~mode:flags ~perm:0o640 in
  let len = 1000000 in
  let raw = Bytes.create len in
  let count = Unix.read file ~buf:raw ~pos:0 ~len in
  let str = Caml.Bytes.sub_string raw 0 count in
  if str = "" then
    default
  else
    str

(* TODO: readfile above doesnt work for reading from the blog. readfile below doesn't work for static content *)
let readfile2 ?(default="") f : string =
  let ic = Caml.open_in f in
  try
    let n = Caml.in_channel_length ic in
    let s = Bytes.create n in
    Caml.really_input ic s 0 n;
    Caml.close_in ic;
    s
  with e ->
    Caml.close_in_noerr ic;
    raise e

let writefile f str : unit =
  let flags = [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] in
  let file = Unix.openfile f ~mode:flags ~perm:0o640 in
  let _ = Unix.write file ~buf:str in
  Unix.close file



let create_id (_ : unit) : int =
  Random.int (Int.pow 2 29)

let inspecT (msg : string) (x : 'a) : unit =
  print_endline ("inspect: " ^ msg ^ ": " ^ x)

let inspect (msg : string) ~(f:'a -> string) (x : 'a) : 'a =
  print_endline ("inspect: " ^ msg ^ ": " ^ (f x));
  x
