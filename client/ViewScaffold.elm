module ViewScaffold exposing (..)

-- builtin

-- lib
import Html
import Html.Attributes as Attrs
import Json.Decode as JSD
import Nineteen.Debug as Debug

-- dark
import Types exposing (..)
import ViewUtils exposing (..)
import JSON
import Url



viewButtons : Model -> Html.Html Msg
viewButtons m =
  let integrationTestButton =
        case m.integrationTestState of
          IntegrationTestExpectation _ ->
            [ Html.a
            [ eventNoPropagation "mouseup" (\_ -> FinishIntegrationTest)
            , Attrs.src ""
            , Attrs.id "finishIntegrationTest"
            , Attrs.class "specialButton"]
            [ Html.text "Finish integration tests" ]]
          IntegrationTestFinished (Ok ()) ->
            [ Html.div [ Attrs.id "integrationTestSignal"
            , Attrs.class "specialButton success"]
            [ Html.text "success"]]
          IntegrationTestFinished (Err msg) ->
            [ Html.div [ Attrs.id "integrationTestSignal"
            , Attrs.class "specialButton failure" ]
            [ Html.text <| "failure: " ++ msg]]
          NoIntegrationTest -> []
      returnButton =
        case m.currentPage of
          Fn _ _ ->
            [Url.linkFor
              (Toplevels m.canvas.offset)
              "specialButton default-link"
              [ Html.text "Return to Canvas"]]
          _ -> []

  in
  Html.div [Attrs.id "buttons"]
    ([ Html.a
      [ eventNoPropagation "mouseup" (\_ -> AddRandom)
      , Attrs.src ""
      , Attrs.class "specialButton"]
      [ Html.text "Random" ]
    , Html.a
      [ eventNoPropagation "mouseup" (\_ -> SaveTestButton)
      , Attrs.src ""
      , Attrs.class "specialButton"]
      [ Html.text "SaveTest" ]
    , Html.a
      [ eventNoPropagation "mouseup" (\_ -> ToggleTimers)
      , Attrs.src ""
      , Attrs.class "specialButton"]
      [ Html.text
          (if m.timersEnabled then "DisableTimers" else "EnableTimers") ]
    , Html.span
      [ Attrs.class "specialButton"]
      [Html.text (Debug.toString m.currentPage)]
    , Html.span
      [ Attrs.class "specialButton"]
      [Html.text ("Active tests: " ++ Debug.toString m.tests)]
    ] ++ integrationTestButton ++ returnButton)

viewError : DarkError -> Html.Html Msg
viewError err =
  case err.message of
    Nothing ->
      Html.div [Attrs.id "status"] [Html.text "Dark"]
    Just msg ->
      let cutMessageAt = 50
          error msg =
            if String.length msg < cutMessageAt
            then
              [ Html.text ("Error: " ++ msg) ]
            else
              let shortMsg = String.left cutMessageAt msg
                  btnText =
                    if err.showDetails
                    then "Hide Details"
                    else "Show Details"
              in
              [ Html.text ("Error: " ++ shortMsg ++ " ... ")
              , Html.a
                  [ Attrs.class "link"
                  , Attrs.href "#"
                  , eventNoPropagation "mouseup" (\_ -> ShowErrorDetails (not err.showDetails)) ]
                  [ Html.text btnText ]
              , Html.div [Attrs.class "more"] [ Html.text msg ]
              ]
      in
      case JSD.decodeString JSON.decodeException msg of
        Err _ -> -- not json, just a regular string
          Html.div
            [ Attrs.id "status"
            , Attrs.classList [("error", True), ("show-details", err.showDetails)] ]
            (error msg)
        Ok exc ->
          Html.div
            [ Attrs.id "status"
            , Attrs.class "error" ]
            (fontAwesome "info-circle" :: error exc.short)
