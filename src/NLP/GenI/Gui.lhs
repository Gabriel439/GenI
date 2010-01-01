% GenI surface realiser
% Copyright (C) 2005 Carlos Areces and Eric Kow
%
% This program is free software; you can redistribute it and/or
% modify it under the terms of the GNU General Public License
% as published by the Free Software Foundation; either version 2
% of the License, or (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program; if not, write to the Free Software
% Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

\chapter{Graphical User Interface} 

\begin{code}
{-# LANGUAGE FlexibleContexts #-}
module NLP.GenI.Gui(guiGeni) where
\end{code}

\ignore{
\begin{code}
import Graphics.UI.WX

import qualified Control.Monad as Monad 
import qualified Data.Map as Map

import Control.Exception
import Data.IORef
import Data.List (isPrefixOf, nub, delete, findIndex)
import Data.Maybe ( fromMaybe )
import Prelude hiding ( catch )
import System.Directory 
import System.Exit (exitWith, ExitCode(ExitSuccess))

import qualified NLP.GenI.Builder as B
import qualified NLP.GenI.BuilderGui as BG
import NLP.GenI.Geni
  ( ProgState(..), ProgStateRef, combine, initGeni
  , prettyResult
  , loadEverything, loadTestSuite, loadTargetSemStr
  )
import NLP.GenI.General (boundsCheck, geniBug, trim, fst3, prettyException)
import NLP.GenI.Btypes (TestCase(..), showFlist,)
import NLP.GenI.Tags (idname, tpolarities, TagElem)
import NLP.GenI.GeniShow (geniShow)
import NLP.GenI.Configuration
  ( Params(..), Instruction, hasOpt
  , hasFlagP, deleteFlagP, setFlagP, getFlagP, getListFlagP
  , parseFlagWithParsec
    --
  , DetectPolaritiesFlg(..)
  , ExtraPolaritiesFlg(..)
  , LexiconFlg(..)
  , MacrosFlg(..)
  , MorphCmdFlg(..)
  , MorphInfoFlg(..)
  , OptimisationsFlg(..)
  , RankingConstraintsFlg(..)
  , RootFeatureFlg(..)
  , TestSuiteFlg(..)
  , TestInstructionsFlg(..)
  , ViewCmdFlg(..)
  --
  , Optimisation(..)
  , BuilderType(..), mainBuilderTypes )
import NLP.GenI.GeniParsers hiding ( choice, label, tab )
import NLP.GenI.GuiHelper

import NLP.GenI.Polarity
import NLP.GenI.PolarityTypes ( readPolarityAttrs, showPolarityAttrs )
import NLP.GenI.Simple.SimpleGui
\end{code}
}

\section{Main Gui}

\begin{code}
guiGeni :: ProgStateRef -> IO() 
guiGeni pstRef = start $ mainGui pstRef
\end{code}

When you first start GenI, you will see this screen:

\begin{center}
\includegraphics[width=0.47\textwidth]{hcar/GenI-main-screenshot.jpg}
\end{center}

It allows you to type in an input semantics (or to modify the one that was
automatically loaded up), select some optimisations and run the realiser.  You
can also opt to run the debugger instead of the realiser (section
\ref{sec:gui:debugger}).

\begin{code}
mainGui :: ProgStateRef -> IO ()
mainGui pstRef 
  = do --
       pst <- readIORef pstRef
       -- Top Window
       f <- frame [text := "Geni Project"]
       -- create statusbar field
       status <- statusField   []
       -- create the file menu
       fileMen   <- menuPane [text := "&File"]
       loadMenIt <- menuItem fileMen [text := "&Open files or configure GenI"]
       quitMenIt <- menuQuit fileMen [text := "&Quit"]
       set quitMenIt [on command := close f ]
       -- create the tools menu
       toolsMen      <- menuPane [text := "&Tools"]
       gbrowserMenIt <- menuItem toolsMen [ text := "&Inspect grammar" 
                                          , help := "Displays the trees in the grammar" ]
       -- create the help menu
       helpMen   <- menuPane [text := "&Help"]
       aboutMeIt <- menuAbout helpMen [help := "About"]
       -- Tie the menu to this window
       set f [ statusBar := [status] 
             , menuBar := [fileMen, toolsMen, helpMen]
             -- put the menu event handler for an about box on the frame.
             , on (menu aboutMeIt) := infoDialog f "About GenI" "The GenI generator.\nhttp://wiki.loria.fr/wiki/GenI" 
             -- event handler for the tree browser
             , on (menu gbrowserMenIt) := do { loadEverything pstRef; treeBrowserGui pstRef }  
             ]
       -- -----------------------------------------------------------------
       -- buttons
       -- -----------------------------------------------------------------
       let config     = pa pst 
           hasSem     = hasFlagP TestSuiteFlg config
       -- Target Semantics
       testSuiteChoice <- choice f [ selection := 0, enabled := hasSem ]
       tsTextBox <- textCtrl f [ wrap := WrapWord
                               , clientSize := sz 400 80
                               , enabled := hasSem 
                               , text := "" ]
       testCaseChoice <- choice f [ selection := 0 
                                  , enabled := hasSem ]
       -- Detect polarities and root feature
       let initialDP = maybe "" showPolarityAttrs (getFlagP DetectPolaritiesFlg config)
           initialRF = maybe "" showFlist (getFlagP RootFeatureFlg config)
       detectPolsTxt <- entry f [ text := initialDP ]
       rootFeatTxt   <- entry f [ text := initialRF ]
       -- Box and Frame for files loaded 
       macrosFileLabel  <- staticText f [ text := getListFlagP MacrosFlg config  ]
       lexiconFileLabel <- staticText f [ text := getListFlagP LexiconFlg config ]
       -- Generate and Debug 
       let genfn = doGenerate f pstRef tsTextBox detectPolsTxt rootFeatTxt
       pauseOnLexChk <- checkBox f [ text := "Inspect lex", tooltip := "Affects debugger only"  ]
       debugBt <- button f [ text := "Debug"
                           , on command := get pauseOnLexChk checked >>= genfn True ]
       genBt  <- button f  [text := "Generate", on command := genfn False False ]
       quitBt <- button f  [ text := "Quit",
                 on command := close f]
       -- -----------------------------------------------------------------
       -- optimisations
       -- -----------------------------------------------------------------
       algoChoiceBox <- radioBox f Vertical (map show mainBuilderTypes)
                        [ selection := case builderType config of
                                       SimpleBuilder -> 0
                                       SimpleOnePhaseBuilder -> 1
                                       NullBuilder   -> 0 ]
       set algoChoiceBox [ on select := toggleAlgo pstRef algoChoiceBox ]
       polChk <- optCheckBox Polarised pstRef f
          [ text := "Polarities"
          , tooltip := "Use the polarity optimisation"
          ]
       useSemConstraintsChk <- antiOptCheckBox NoConstraints pstRef f
         [ text := "Sem constraints"
         , tooltip := "Use any sem constraints the user provides"
         ]
       earlyNaChk <- optCheckBox EarlyNa pstRef f
          [ text := "NA detection"
          , tooltip := "Early detection of nodes that cannot be adjoined to"
          ]
       semfilterChk <- optCheckBox SemFiltered pstRef f
         [ text := "Semantic filters"
         , tooltip := "(2p only) Filter away semantically incomplete structures before adjunction phase"
         ]
       extrapolText <- staticText f 
         [ text := maybe "" showLitePm $ getFlagP ExtraPolaritiesFlg config
         , tooltip := "Use the following additional polarities" 
         ]
       -- commands for the checkboxes
       let togglePolStuff = do c <- get polChk checked
                               set extrapolText [ enabled := c ]
       set polChk [on command :~ (>> togglePolStuff) ]
       -- -----------------------------------------------------------------
       -- layout; packing it all together
       -- -----------------------------------------------------------------
       -- set any last minute handlers, run any last minute functions
       let onLoad =
            do -- errHandler title err = errorDialog f title (show err)
               set macrosFileLabel  [ text := getListFlagP MacrosFlg config ]
               set lexiconFileLabel [ text := getListFlagP LexiconFlg config ]
               -- set tsFileLabel      [ text := getListFlagP TestSuiteFlg config ]
               -- read the test suite if there is one
               case getListFlagP TestInstructionsFlg config of
                 [] -> do set testSuiteChoice [ enabled := False, items := [] ]
                          set testCaseChoice  [ enabled := False, items := [] ]
                 is ->
                   do -- handler for selecting a test suite
                      let imap = Map.fromList $ zip [0..] is
                          onTestSuiteChoice = do
                            sel <- get testSuiteChoice selection
                            case Map.lookup sel imap of
                              Nothing -> geniBug $ "No such index in test suite selector (gui): " ++ show sel
                              Just t  -> loadTestSuiteAndRefresh f pstRef t tsTextBox testCaseChoice
                      set testSuiteChoice [ enabled := True, items := map fst is
                                          , on select := onTestSuiteChoice, selection := 0 ]
                      set testCaseChoice  [ enabled := True ]
                      onTestSuiteChoice -- load the first suite
       --
       set loadMenIt [ on command := do configGui pstRef onLoad ]
       onLoad
       togglePolStuff
       --
       let labeledRow l w = row 1 [ label l, hfill (widget w) ]
       let gramsemBox = boxed "Files last loaded" $ 
                   hfill $ column 1 
                     [ labeledRow "trees:"   macrosFileLabel
                     , labeledRow "lexicon:" lexiconFileLabel
                     ]
           optimBox =  --boxed "Optimisations " $ -- can't used boxed with wxwidgets 2.6 -- bug?
                    column 5 [ label "Algorithm"
                             , dynamic $ widget algoChoiceBox
                             , label "Optimisations"
                             , dynamic $ widget polChk 
                             , row 5 [ label "  ", column 5 
                                     [ dynamic $ row 5 [ label "Extra: ", widget extrapolText ] ] ]
                             , dynamic $ widget useSemConstraintsChk
                             , dynamic $ widget semfilterChk 
                             , dynamic $ widget earlyNaChk
                             ]
       set f [layout := column 5 [ gramsemBox
                   , row 5 [ fill $ -- boxed "Input Semantics" $ 
                             hfill $ column 5 
                               [ labeledRow "test suite: " testSuiteChoice
                               , labeledRow "test case: "  testCaseChoice
                               , fill  $ widget tsTextBox
                               , row 1 [ label "detect pols: "
                                       , hfill (widget detectPolsTxt)
                                       , glue
                                       , label "root feature: "
                                       , hfill (widget rootFeatTxt)
                                       ]
                               ]
                           , vfill optimBox ]
                    -- ----------------------------- Generate and quit 
                   , row 1 [ widget quitBt 
                          , hfloatRight $ row 5 [ widget pauseOnLexChk, widget debugBt, widget genBt ]] ]
            , clientSize := sz 525 325
            , on closing := exitWith ExitSuccess 
            ]

-- Note the following point about anti-optimisations: An anti-optimisation
-- disables a default behaviour which is assumed to be "optimisation".  But of
-- course we don't want to confuse the GUI user, so we confuse the programmer
-- instead: Given an anti-optimisation DisableFoo, we have a check box UseFoo.  If
-- UseFoo is checked, we remove DisableFoo from the list; if it is unchecked, we
-- add it to the list.  This is the opposite of the default behaviour, but the
-- result, I hope, is intuitive for the user.
toggleAlgo :: (Selection a, Items a String) => ProgStateRef -> a -> IO ()
toggleAlgo pstRef box =
 do asel   <- get box selection
    aitems <- get box items
    let selected = aitems !! asel
        btable = zip (map show mainBuilderTypes) mainBuilderTypes
        btype = case [ b | (name, b) <- btable, name == selected ] of
                []  -> geniBug $ "Unknown builder type " ++ selected
                [b] -> b
                _   -> geniBug $ "More than one builder has the name " ++ selected
    modifyIORef pstRef (\x -> x { pa = (pa x) { builderType = btype } })

optCheckBox, antiOptCheckBox ::
  Optimisation -> ProgStateRef
               -> Window a -> [Prop (CheckBox ())]
               -> IO (CheckBox ())

-- | Checkbox for enabling or disabling an optimisation
--   You need not set the checked or on command attributes
--   as this is done for you (but you can if you want,
--   setting checked will override the default, and any
--   command you set will be run before the toggle stuff)
optCheckBox = optCheckBoxHelper id

-- | Same as 'optCheckBox' but for anti-optimisations
antiOptCheckBox = optCheckBoxHelper not

optCheckBoxHelper :: (Bool -> Bool) -> Optimisation -> ProgStateRef
                  -> Window a -> [Prop (CheckBox ())]
                  -> IO (CheckBox ())
optCheckBoxHelper idOrNot o pstRef f as =
  do pst <- readIORef pstRef
     chk <- checkBox f $ [ checked := idOrNot $ hasOpt o $ pa pst ] ++ as
     set chk [ on command :~ (>> onCheck chk) ]
     return chk
  where
   onCheck chk =
    do isChecked <- get chk checked
       pst <- readIORef pstRef
       let config  = pa pst
           modopt  = if idOrNot isChecked then (o:) else delete o
           newopts = nub.modopt $ getListFlagP OptimisationsFlg config
       modifyIORef pstRef (\x -> x{pa = setFlagP OptimisationsFlg newopts (pa x)})

-- --------------------------------------------------------------------
-- Loading files
-- --------------------------------------------------------------------

-- | Load the given test suite and update the GUI accordingly.
--   This is used when you first start the graphical interface
--   or when you run the configuration menu.
loadTestSuiteAndRefresh :: (Textual a, Selecting b, Selection b, Items b String) 
              => Window w -> ProgStateRef -> Instruction -> a -> b -> IO ()
loadTestSuiteAndRefresh f pstRef (suitePath,mcs) tsBox caseChoice =
  do (loadTestSuite pstRef >> return ())
       `catch` \e -> errorDialog f ("Error reading test suite " ++ suitePath) (show e)
     pst <- readIORef pstRef
     let suite   = tsuite pst
         theCase = tcase pst
         suiteCases = case filter (\c -> tcName c `elem` cs) suite of
                       []  -> suite
                       res -> res
           where cs = fromMaybe [] mcs
         suiteCaseNames = map tcName suiteCases
     -- we number the cases for easy identification, putting 
     -- a star to highlight the selected test case (if available)
     let numfn :: Int -> String -> String
         numfn n t = (if t == theCase then "* " else "")
                      ++ (show n) ++ ". " ++ t
         tcaseLabels = zipWith numfn [1..] suiteCaseNames
     -- we select the first case in cases_, if available
     caseSel <- if null theCase
                   then return 0
                   else case findIndex (== theCase) suiteCaseNames of
                               Nothing -> do errorDialog f "" ("No such test case: " ++ theCase)
                                             return 0
                               Just i  -> return i
     ----------------------------------------------------
     -- handler for selecting a test case
     ----------------------------------------------------
     let displaySemInput (TestCase { tcSem = si, tcSemString = str }) =
           geniShow $ toSemInputString si str
     let onTestCaseChoice = do
         csel <- get caseChoice selection
         if boundsCheck csel suite
           then do let s = (suiteCases !! csel)
                   set tsBox [ text :~ (\_ -> displaySemInput s) ]
           else geniBug $ "Gui: test case selector bounds check error: " ++
                          show csel ++ " of " ++ show tcaseLabels ++ "\n"
     ----------------------------------------------------
     set caseChoice [ items := tcaseLabels 
                  , selection := caseSel
                  , on select := onTestCaseChoice ]
     when (not $ null suite) onTestCaseChoice -- run this once
\end{code}
 
% --------------------------------------------------------------------
\section{Configuration}
% --------------------------------------------------------------------

The configuration GUI aims to a provide a graphical substitute for the command
line switches.  Note you cannot yet select optimisations and test cases from
this window; use the main window instead.  Note also that changes to GenI tend
to start from the command line switches and only percolate to the GUI when time
permits.  For full control of GenI, see \verb!geni --help!.

\begin{center}
\emph{TODO: screenshot wanted}
\end{center}

\begin{code}
-- | 'configGui' @pstRef loadFn@ provides the configuration GUI. The continuation
--   @loadFn@ tells us what to do when the user closes this window.
configGui ::  ProgStateRef -> IO () -> IO () 
configGui pstRef loadFn = do 
  pst <- readIORef pstRef
  let config = pa pst
  -- 
  f  <- frame []
  p  <- panel f []
  nb <- notebook p []
  let browseTxt = "Browse"
  --
  let fakeBoxed title lst = hstretch $ column 3 $ map hfill $ 
        [ hrule 1 , alignRight $ label title, vspace 5 ] 
        ++ map hfill lst
  let shortSize = sz 10 25
  let longSize  = sz 20 25
  -- -----------------------------------------------------------------
  -- basic options tab
  -- -----------------------------------------------------------------
  pbas <- panel nb []
  -- files loaded (labels)
  macrosFileLabel  <- staticText pbas [ text := getListFlagP MacrosFlg config  ]
  lexiconFileLabel <- staticText pbas [ text := getListFlagP LexiconFlg config ]
  tsFileLabel      <- staticText pbas [ text := getListFlagP TestSuiteFlg config ]
  -- "Browse buttons"
  macrosBrowseBt  <- button pbas [ text := browseTxt ]
  lexiconBrowseBt <- button pbas [ text := browseTxt ]
  tsBrowseBt      <- button pbas [ text := browseTxt ]
  -- root feature
  detectPolsTxt <- entry pbas
    [ text := maybe "" showPolarityAttrs (getFlagP DetectPolaritiesFlg config)
    , size := longSize ]
  rootFeatTxt <- entry pbas
    [ text := maybe "" showFlist (getFlagP RootFeatureFlg config)
    , size := longSize ]
  let layFiles = [ row 1 [ label "trees:" 
                         , fill $ widget macrosFileLabel
                         , widget macrosBrowseBt  ]
                 , row 1 [ label "lexicon:"
                         , fill $ widget lexiconFileLabel
                         , widget lexiconBrowseBt ] 
                 , row 1 [ label "test suite:"
                         , fill $ widget tsFileLabel
                         , widget tsBrowseBt ]
                 , hspace 5
                 , hfill $ vrule 1
                 , row 3 [ label "detect polarities"
                         , hglue
                         , rigid $ widget detectPolsTxt ]
                 , row 3 [ label "root features"
                         , hglue
                         , rigid $ widget rootFeatTxt ]  
                 ] 
    -- the layout for the basic stuff
  let layBasic = dynamic $ container pbas $ -- boxed "Basic options" $ 
                   hfloatLeft $ dynamic $ fill $ column 4 $ map (dynamic.hfill) $ layFiles 
  -- -----------------------------------------------------------------
  -- advanced options tab
  -- -----------------------------------------------------------------
  padv <- panel nb []
  -- XMG tools 
  viewCmdTxt <- entry padv 
    [ tooltip := "Command used for XMG tree viewing"
    , text := getListFlagP ViewCmdFlg config ]
  let layXMG = fakeBoxed "XMG tools" 
                [ row 3 [ label "XMG view command"
                        , marginRight $ hfill $ widget viewCmdTxt ] ]
  -- polarities
  extraPolsTxt <- entry padv 
    [ text := maybe "" showLitePm $ getFlagP ExtraPolaritiesFlg config
    , size := shortSize ]
  let layPolarities = fakeBoxed "Polarities" [ hfill $ row 1 
          [ label "extra polarities", rigid $ widget extraPolsTxt ] ]
  -- morphology
  morphFileLabel    <- staticText padv [ text := getListFlagP MorphInfoFlg config ]
  morphFileBrowseBt <- button padv [ text := browseTxt ]
  morphCmdTxt    <- entry padv 
    [ tooltip := "Commmand used for morphological generation" 
    , text    := getListFlagP MorphCmdFlg config ]
  let layMorph = fakeBoxed "Morphology" 
                   [ row 3 [ label "morph info:"
                           , expand $ hfill $ widget morphFileLabel
                           , widget morphFileBrowseBt ]
                   , row 3 [ label "morph command"
                           , (marginRight.hfill) $ widget morphCmdTxt ] ]
  -- put the whole darn thing together
  let layAdvanced = hfloatLeft $ container padv $ column 10 
        $ [ layXMG, layPolarities, layMorph]
  -- -----------------------------------------------------------------
  -- browse button action
  --
  -- When the user clicks on a Browse button, an open file dialogue should pop up.
  -- It gets its value from the file label on its left (passed in as an argument),
  -- and updates said label when the user has made a selection.
  -- -----------------------------------------------------------------
  -- helper functions
  curDir <- getCurrentDirectory
  let curDir2 = curDir ++ "/"
      trim2 pth = if curDir2 `isPrefixOf` pth2
                     then drop (length curDir2) pth2
                     else pth2
                  where pth2 = trim pth
  let onBrowse theLabel 
       = do rawFilename <- get theLabel text
            let filename = trim2 rawFilename
                filetypes = [("Any file",["*","*.*"])]
            fsel <- fileOpenDialog f False True
                      "Choose your file..." filetypes "" filename
            case fsel of
              -- if the user does not select any file there are no changes
              Nothing   -> return () 
              Just file -> set theLabel [ text := trim2 file ]
  -- end onBrowse
  -- activate those "Browse" buttons
  let setBrowse w l = set w [ on command := onBrowse l ]
  setBrowse macrosBrowseBt macrosFileLabel
  setBrowse lexiconBrowseBt lexiconFileLabel 
  setBrowse tsBrowseBt tsFileLabel
  setBrowse morphFileBrowseBt morphFileLabel
  -- -----------------------------------------------------------------
  -- config GUI layout
  -- -----------------------------------------------------------------
  let parsePol = parseFlagWithParsec "polarities"    geniPolarities
      parseRF  = parseFlagWithParsec "root features" geniFeats
      onLoad 
       = do macrosVal <- get macrosFileLabel text
            lexconVal <- get lexiconFileLabel text
            tsVal     <- get tsFileLabel text
            --
            detectPolsVal <- get detectPolsTxt text
            rootCatVal  <- get rootFeatTxt  text
            extraPolVal <- get extraPolsTxt text
            --
            viewVal   <- get viewCmdTxt text 
            --
            morphCmdVal  <- get morphCmdTxt text
            morphInfoVal <- get morphFileLabel text
            --
            let maybeSet fl fn x =
                   if null x then deleteFlagP fl else setFlagP fl (fn x)
                maybeSetStr fl x = maybeSet fl id x
            let setConfig = id
                  . (maybeSetStr   MacrosFlg macrosVal)
                  . (maybeSetStr LexiconFlg lexconVal)
                  . (maybeSetStr TestSuiteFlg tsVal)
                  . (maybeSetStr TestInstructionsFlg [(tsVal,Nothing)])
                  . (setFlagP DetectPolaritiesFlg (readPolarityAttrs detectPolsVal))
                  . (maybeSet RootFeatureFlg parseRF rootCatVal)
                  . (maybeSet ExtraPolaritiesFlg parsePol extraPolVal)
                  . (maybeSetStr ViewCmdFlg viewVal)
                  . (maybeSetStr MorphCmdFlg morphCmdVal)
                  . (maybeSetStr MorphInfoFlg morphInfoVal)
            modifyIORef pstRef $ \x -> x { pa = setConfig (pa x) }
            loadFn 
  -- end onLoad
    -- the button bar
  cancelBt <- button p 
    [ text := "Cancel", on command := close f ]
  loadBt   <- button p 
    [ text := "Load", on command := do { onLoad; close f } ]
  let layButtons = hfill $ row 1 
        [ hfloatLeft  $ widget cancelBt
        , hfloatRight $ widget loadBt ]
  --
  set f [ layout := dynamic $ fill $ container p $ column 0 
           [ fill $ tabs nb [ tab "Basic" layBasic
                            , tab "Advanced" layAdvanced ] 
           , hfill $ layButtons ]
        ] 
\end{code}
 
% --------------------------------------------------------------------
\section{Generation}
% --------------------------------------------------------------------

\begin{code}
-- | 'doGenerate' parses the target semantics, then calls the generator and
-- displays the result in a results gui (below).
doGenerate :: Textual tb => Window a -> ProgStateRef
                         -> tb -- ^ sem
                         -> tb -- ^ polarities to detect
                         -> tb -- ^ root feature
                         -> Bool -> Bool -> IO ()
doGenerate f pstRef sembox detectPolsTxt rootFeatTxt useDebugger pauseOnLex =
 do let parseRF  = parseFlagWithParsec "root features" geniFeats
    rootCatVal    <- get rootFeatTxt text
    detectPolsVal <- get detectPolsTxt text
    --
    let maybeSet fl fn x =
           if null x then deleteFlagP fl else setFlagP fl (fn x)
    let setConfig = id
          . (maybeSet RootFeatureFlg parseRF rootCatVal)
          . (setFlagP DetectPolaritiesFlg (readPolarityAttrs detectPolsVal))
    modifyIORef pstRef $ \p -> p { pa = setConfig (pa p), warnings = [] }
    loadEverything pstRef
    sem <- get sembox text
    loadTargetSemStr pstRef sem
    --
    pst <- readIORef pstRef
    let config = pa pst
        withBuilderGui a =
          case builderType config of
          NullBuilder   -> error "No gui available for NullBuilder"
          SimpleBuilder         -> a simpleGui_2p
          SimpleOnePhaseBuilder -> a simpleGui_1p
    --
    let doDebugger bg = debugGui bg pstRef pauseOnLex
        doResults  bg = resultsGui bg pstRef
    do catch (withBuilderGui $ if useDebugger then doDebugger else doResults)
             (handler "Error during realisation")
  -- FIXME: it would be nice to distinguish between generation and ts
  -- parsing errors
 `catch` (handler "Error parsing with your input")
 where
   handler title err = errorDialog f title (prettyException err)
\end{code}

When surface realisation is complete, we display a results window with various
tabs for intermediary results in lexical selection, derived trees, derivation
trees and generation statistics.

\begin{center}
\emph{TODO: screenshot wanted}
\end{center}

\begin{code}
resultsGui :: BG.BuilderGui -> ProgStateRef -> IO ()
resultsGui builderGui pstRef =
 do -- results window
    f <- frame [ text := "Results"
               , fullRepaintOnResize := False
               , layout := stretch $ label "Generating..."
               , clientSize := sz 300 300
               ]
    p    <- panel f []
    nb   <- notebook p []
    -- realisations tab
    (results,_,summTab,resTab) <- BG.resultsPnl builderGui pstRef nb
    -- ranking tab
    pst <- readIORef pstRef
    let useRanking = hasFlagP RankingConstraintsFlg (pa pst)
    rankTab <- messageGui nb . unlines . map (prettyResult pst) $ results
    -- tabs
    let myTabs = [ tab "summary"       summTab
                 , tab "realisations"  resTab
                 ] ++
                 (if useRanking then [ tab "ranking" rankTab ] else [])
    -- pack it all together
    set f [ layout := container p $ column 0 [ tabs nb myTabs ]
          , clientSize := sz 700 600 ]
    return ()
\end{code}

% --------------------------------------------------------------------
\section{Debugging}
\label{sec:gui:debugger}
% --------------------------------------------------------------------

Instead of going directly to the results window, you could instead use the
interactive debugger which GenI provides.  The debugger shows a separate tab
for each phase in surface realisation (lexical selection, filtering, building).

\begin{center}
\includegraphics[width=0.47\textwidth]{hcar/GenI-debugger-screenshot.jpg}
\end{center}

\begin{code}
-- | We provide here a universal debugging interface, which makes use of some
--   parameterisable bits as defined in the BuilderGui module.
debugGui :: BG.BuilderGui -> ProgStateRef -> Bool -> IO ()
debugGui builderGui pstRef pauseOnLex =
 do config <- pa `fmap` readIORef pstRef
    let btype = show $ builderType config
    --
    f <- frame [ text := "GenI Debugger - " ++ btype ++ " edition"
               , fullRepaintOnResize := False
               , clientSize := sz 300 300 ]
    p    <- panel f []
    nb   <- notebook p []
    -- generation step 1
    initStuff <- initGeni pstRef
    let (cand,_)   = unzip $ B.inCands initStuff
    -- continuation for candidate selection tab
    let step2 newCands =
         do -- generation step 2.A (run polarity stuff)
            let newInitStuff = initStuff { B.inCands = map (\x -> (x, -1)) newCands }
                (input2, _, autstuff) = B.preInit newInitStuff config
            -- automata tab
            let (auts, _, finalaut, _) = autstuff
            autPnl <- if hasOpt Polarised config
                         then fst3 `fmap` polarityGui nb auts finalaut
                         else messageGui nb "polarity filtering disabled"
            -- generation step 2.B (start the generator for each path)
            debugPnl <- BG.debuggerPnl builderGui nb config input2 btype
            let autTab   = tab "automata" autPnl
                debugTab = tab (btype ++ "-session") debugPnl
                genTabs  = if hasOpt Polarised config
                           then [ autTab, debugTab ] else [ debugTab ]
            --
            set f [ layout := container p $ tabs nb genTabs
                  , clientSize := sz 700 600 ]
            return ()
    -- candidate selection tab
    pst <- readIORef pstRef
    (canPnl,_,_) <- if pauseOnLex
                    then pauseOnLexGui pst nb cand step2
                    else candidateGui  pst nb cand
    -- basic tabs
    let basicTabs = [ tab "lexical selection" canPnl ]
    --
    set f [ layout := container p $ tabs nb basicTabs
          , clientSize := sz 700 600 ]
    -- display all tabs if we are not told to pause on lex selection
    when (not pauseOnLex) (step2 cand)
\end{code}

\subsection{Stepping through the debugger}

The interactive debugger can have a diffrent GUI for each realisation algorithm.
Here we will discuss the interface for the Simple 2-Phase algorithm which \geni
uses by default.  The interfaces for other algorithms are likely to very similar.

\begin{center}
\includegraphics[width=0.47\textwidth]{images/debugger-features.png}
\end{center}

The debugger allows you to step through chart generation.  Using the 'Step by'
button, you can walk through an arbitrary number of steps, where each step
consists in pulling one item of the agenda, combining it with the chart and
putting some of the results back on to the agenda (or the trash, or results
pile as the case may be).  New chart items produced on each step typically have
one of their nodes highlighted in red.  This indicates that the node was the
site of the most recent ``event''.  For example in the substitution phase, the
red node indicates where the substitution operation was performed; whereas in
the adjunction phase, it could either indicate where adjunction was performed
or where a null-adjunction constraint was applied.

If you select the ``show features'' checkbox, all nodes in the chart item will
be expanded to reveal the underlying feature structures.  The components of this
expanded representation are segmented into the following boxes:

\vspace{1em}
\begin{tabular}{ll}
\begin{minipage}{0.10\textwidth}
\includegraphics[width=\textwidth]{images/debugger-features-focus.png}
\end{minipage} &
\begin{minipage}{0.70\textwidth}
\begin{enumerate}
\item Summary: here, \verb!n:j.m! indicates that the category is \verb!n!,
      that the top \verb!idx! feature is associated with \verb'j' and the
      bottom one with \verb!m!.
\item Decorations: here, $\downarrow$ indicates that this is a TAG substitution
      node, following the usual conventions in the literature.
\item The top feature structure
\item The bottom feature structure
\end{enumerate}
\end{minipage} \\
\end{tabular}

% --------------------------------------------------------------------
\section{Tree browser}
\label{sec:treebrowser_gui}
% --------------------------------------------------------------------

The GenI tree browser displays all the TAG trees in the grammar grouped
according to the semantics with which they are associated.

\begin{code}
-- Note that we can't just reuse candidateGui's code because we label and sort
-- the trees differently.  Here we ignore the arguments in tree semantics, and
-- we display the tree polarities in its label.
treeBrowserGui :: ProgStateRef -> IO () 
treeBrowserGui pstRef = do
  pst <- readIORef pstRef
  -- ALL THE TREES in the grammar... muahahaha!
  let semmap = combine (gr pst) (le pst)
  -- browser window
  f <- frame [ text := "Tree Browser" 
             , fullRepaintOnResize := False 
             ] 
  -- the heavy GUI artillery
  let sem      = Map.keys semmap
      --
      lookupTr k = Map.findWithDefault [] k semmap
      treesfor k = Nothing : (map Just $ lookupTr k)
      labsfor  k = ("___" ++ k ++ "___") : (map fn $ lookupTr k)
                   where fn    t = idname t ++ polfn (tpolarities t)
                         polfn p = if Map.null p 
                                   then "" 
                                   else " (" ++ showLitePm p ++ ")"
      --
      trees    = concatMap treesfor sem
      itNlabl  = zip trees (concatMap labsfor sem)
  (browser,_,_) <- tagViewerGui pst f "tree browser" "grambrowser" itNlabl
  -- the button panel
  let numTrees = length trees - length sem
  quitBt <- button f [ text := "Close", on command := close f ]
  -- pack it all together 
  set f [ layout := column 5 [ browser, 
                       row 5 [ label ("number of trees: " ++ show numTrees)
                             , hfloatRight $ widget quitBt ] ]
        , clientSize := sz 700 600 ]
  return ()
\end{code}
