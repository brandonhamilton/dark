module Editor exposing (..)

-- Dark
import Types exposing (..)

model2editor : Model -> Editor
model2editor m =
  case m.clipboard of
    Nothing -> { clipboard = Nothing }
    Just c ->
      { clipboard = Nothing }
