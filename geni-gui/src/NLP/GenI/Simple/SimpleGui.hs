-- GenI surface realiser
-- Copyright (C) 2005 Carlos Areces and Eric Kow
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module NLP.GenI.Simple.SimpleGui where

import Control.Applicative ( (<$>) )
import Control.Arrow ( (***) )
import Control.Monad.Trans.Error
import Data.IORef
import Data.List ( sort, partition )
import Data.Maybe ( fromMaybe )
import qualified Data.Map as Map
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL

import qualified Data.GraphViz as GV
import qualified Data.GraphViz.Attributes.Complete as GV
import Graphics.UI.WX

import NLP.GenI
    ( ProgState(pa), runGeni
    , GeniResults(..) , GeniResult(..)
    , GeniSuccess(..), GeniError(..), isSuccess
    )
import NLP.GenI.Configuration ( Params(..) )
import NLP.GenI.FeatureStructure ( AvPair(..) )
import NLP.GenI.General ( snd3, buckets )
import NLP.GenI.GeniVal ( mkGConstNone, GeniVal )
import NLP.GenI.Graphviz ( GraphvizShow(..), gvUnlines )
import NLP.GenI.GraphvizShow
    ( graphvizShowDerivation, GvItem(..)
    , gvItemSetFlag, GNodeHighlights, Highlights )
import NLP.GenI.GuiHelper
    ( messageGui, tagViewerGui, maybeSaveAsFile, debuggerPanel
    , Debugger (..)
    , DebuggerItemBar, GvIO, newGvRef, GraphvizGuiSt(..), viewTagWidgets
    , XMGDerivation(getSourceTrees), modifyGvItems
    )
import NLP.GenI.LexicalSelection ( CustomSem(..) )
import NLP.GenI.Morphology (LemmaPlus(..))
import NLP.GenI.Polarity hiding ( finalSt )
import NLP.GenI.Pretty
import NLP.GenI.Simple.SimpleBuilder
    ( simpleBuilder, SimpleStatus, SimpleItem(..), SimpleGuiItem(..)
    , unpackResult ,step
    , theResults, theAgenda, theHoldingPen, theChart, theTrash
    )
import NLP.GenI.Statistics (Statistics, showFinalStats, emptyStats)
import NLP.GenI.TestSuite
import NLP.GenI.Tag (dsChild, TagItem(..))
import NLP.GenI.TreeSchema ( GNode(..), GType(..) )
import qualified NLP.GenI.Builder    as B
import qualified NLP.GenI.BuilderGui as BG

-- --------------------------------------------------------------------
-- Interface
-- --------------------------------------------------------------------

simpleGui2p, simpleGui1p :: BG.BuilderGui
simpleGui2p = simpleGui True
simpleGui1p = simpleGui False

simpleGui :: Bool -> BG.BuilderGui
simpleGui twophase = BG.BuilderGui
    { BG.resultsPnl  = resultsPnl twophase
    , BG.summaryPnl  = summaryGui
    , BG.debuggerPnl = simpleDebuggerTab twophase
    }

resultsPnl :: Bool
           -> ProgState
           -> CustomSem sem
           -> Window a
           -> TestCase sem
           -> IO ([GeniResult], Statistics, Layout, Layout)
resultsPnl twophase pst wrangler f tc = do
    mresults <- runErrorT $
        runGeni pst wrangler (simpleBuilder twophase) tc
    case mresults of
        Left err  -> do
            (resultsL, _, _) <- realisationsGui pst f []
            summaryL         <- messageGui f err
            return ([], emptyStats, summaryL, resultsL)
        Right (gresults, finalSt) -> do
            let sentences = grResults    gresults
                stats     = grStatistics gresults
            (resultsL, _, _) <- realisationsGui pst f $ theResults finalSt
            summaryL         <- summaryGui pst f sentences stats
            return (sentences, stats, summaryL, resultsL)

-- --------------------------------------------------------------------
-- Results
-- --------------------------------------------------------------------

-- Derived Trees

-- | Browser for derived/derivation trees, except if there are no results, we show a
--   message box
realisationsGui :: ProgState -> Window a -> [SimpleItem]
                -> GvIO () (GvItem Bool SimpleItem)
realisationsGui _   f [] = do
    m <- messageGui f "No results found"
    g <- newGvRef () ""
    return (m, g, return ())
realisationsGui pst f resultsRaw = do
    tagViewerGui config f tip "derived" itNlabl
  where
    config = pa pst
    tip = "result"
    mkItNLabl x = GvItem (siToSentence x) False x
    itNlabl = map mkItNLabl resultsRaw

summaryGui :: ProgState
           -> Window a
           -> [GeniResult]
           -> Statistics -> IO Layout
summaryGui _ f results stats = do
    p <- panel f []
    statsTxt <- textCtrl p [ text := showFinalStats stats ]
    t <- textCtrl p [ text := T.unpack msg ]
    saveBt <- button p [ text := "Save to file"
                       , on command := maybeSaveAsFile f msg ]
    return $ fill $ container p $ column 1
        [ hfill $ label "Performance data"
        , hfill $ widget statsTxt
        , hfill $ label $ "Realisations (" ++ show totalResults ++ " found)"
        , fill  $ widget t
        , hfloatRight $ widget saveBt
        ]
  where
    (succeses, errors) = partitionGeniResult results
    taggedResults = concatMap sentences succeses
    resultBuckets = buckets snd taggedResults
    sentences gr  = map (\r -> (grOrigin gr, r)) (grRealisations gr)
    prettyBucket (s, xys) = s <+> parens instances
      where
        instances = if length ys == 1
                       then ys_str
                       else pretty (length ys) <+> "instances:" <+> ys_str
        ys = map fst xys
        ys_str = T.intercalate ", " . map pretty . sort $ ys
    msg = T.unlines $ concatMap fromError errors
                 ++ (if null succeses
                        then [ "(none)" ]
                        else map prettyBucket resultBuckets)
    totalResults  = length taggedResults
    fromError (GeniError e) = e

partitionGeniResult :: [GeniResult] -> ([GeniSuccess],[GeniError])
partitionGeniResult results = (map unSucc *** map unErr)
                            $ partition isSuccess results
  where
    unSucc (GSuccess x) = x
    unSucc _ = error "NLP.GenI.Simple.SimpleGui unSucc"
    unErr  (GError x) = x
    unErr  _ = error "NLP.GenI.Simple.SimpleGui unErr"

-- --------------------------------------------------------------------
-- Debugger
-- --------------------------------------------------------------------

simpleDebuggerTab :: Bool
                  -> ProgState
                  -> Window a
                  -> B.Input
                  -> String
                  -> ([GeniResult] -> Statistics -> IO ())
                  -> IO Layout
simpleDebuggerTab twophase pst f input name job = do
    debuggerPanel dbg pst f input
  where
    dbg :: Debugger SimpleStatus Bool SimpleItem
    dbg = Debugger
        { dBuilder    = simpleBuilder twophase
        , dToGv       = stToGraphviz
        , dControlPnl = simpleItemBar (pa pst)
        , dNext       = job
        , dCacheDir   = name
        }

stToGraphviz :: SimpleStatus -> [GvItem Bool SimpleItem]
stToGraphviz st =
    concat [ agenda, auxAgenda, chart, trash, results ]
  where
    agenda    = section "AGENDA"    $ theAgenda    st
    auxAgenda = section "HOLDING"   $ theHoldingPen st
    trash     = section "TRASH"     $ theTrash     st
    chart     = section "CHART"     $ theChart     st
    results   = section "RESULTS"   $ theResults   st
    --
    section n i = hd : map tlFn i
      where
        hd     = GvHeader ("___" <> n <> "___")
        tlFn x = GvItem (siToSentence x <+> prettyPaths x) False x
    prettyPaths  = parens . prettyPolPaths . siPolpaths

simpleItemBar :: Params -> DebuggerItemBar SimpleStatus Bool SimpleItem
simpleItemBar config f gvRef updaterFn = do
    ib <- panel f []
    phaseTxt   <- staticText ib [ text := "" ]
    detailsChk <- checkBox ib [ text := "Show features"
                              , checked := False ]
    viewTagLay <- viewTagWidgets ib gvRef config
    -- handlers
    let onDetailsChk = do
            isDetailed <- get detailsChk checked
            modifyGvItems gvRef (gvItemSetFlag isDetailed)
            updaterFn
    set detailsChk [ on command := onDetailsChk ]
    --
    let lay = hfloatCentre . container ib . row 5 $
               [ hspace 5
               , widget phaseTxt
               , hglue
               , widget detailsChk
               , hglue
               , viewTagLay
               , hspace 5 ]
    let onUpdate = do
            status <- gvcore `fmap` readIORef gvRef
            set phaseTxt [ text := show (step status) ]
    return (lay, onUpdate)

-- --------------------------------------------------------------------
-- Miscellaneous
-- -------------------------------------------------------------------

-- to have the basic GraphvizShow functionality
newtype SimpleItemWrapper = SimpleItemWrapper { fromSimpleItemWrapper :: SimpleItem }

instance TagItem SimpleItemWrapper where
    tgIdName    = siIdname . siGuiStuff . fromSimpleItemWrapper
    tgIdNum     = siId . fromSimpleItemWrapper
    tgSemantics = siFullSem . siGuiStuff . fromSimpleItemWrapper
    tgTree si   =
        lookupOrBug <$> siDerived (fromSimpleItemWrapper si)
      where
        lookupOrBug k = fromMaybe (buggyNode k) $ Map.lookup k nodeMap
        nodeMap = fromListUsingKey gnname (siNodes (fromSimpleItemWrapper si))
        buggyNode k = GN
            { gup     = [ AvPair "cat"
                             (mkGConstNone $ "ERROR looking up" <+> k)
                        ]
            , gdown   = []
            , gnname  = "ERROR"
            , glexeme = []
            , gtype   = Other
            , ganchor  = False
            , gaconstr = False
            , gorigin = "ERROR"
            }

fromListUsingKey :: Ord k => (a -> k) -> [a] -> Map.Map k a
fromListUsingKey f xs = Map.fromList [ (f x, x) | x <- xs ]

instance XMGDerivation SimpleItem where
    -- Note: this is XMG-related stuff
    getSourceTrees it = map dsChild (siDerivation it)

instance GraphvizShow (GvItem Bool SimpleItem) where
    graphvizLabel (GvHeader _)     = ""
    graphvizLabel g@(GvItem _ _ c) =
        gvUnlines $ graphvizLabel (highlightSimpleItem g)
                  : map TL.pack (siDiagnostic (siGuiStuff c))

    graphvizParams = graphvizParams . highlightSimpleItem

    graphvizShowAsSubgraph _ (GvHeader _) = []
    graphvizShowAsSubgraph p g@(GvItem _ _ it) =
           graphvizShowAsSubgraph (p `TL.append` "TagElem") (highlightSimpleItem g)
        ++ graphvizShowDerivation (siDerivation it)

highlightSimpleItem :: GvItem Bool SimpleItem -> GvItem GNodeHighlights SimpleItemWrapper
highlightSimpleItem (GvHeader h)    = GvHeader h
highlightSimpleItem (GvItem l f it) = GvItem l (f, highlights) (SimpleItemWrapper it)
  where
    highlights :: Highlights (GNode GeniVal)
    highlights n =
        if gnname n `elem` siHighlight (siGuiStuff it)
           then Just (GV.X11Color GV.Red)
           else Nothing

siToSentence :: SimpleItem -> T.Text 
siToSentence si =
    case unpackResult si of
        []    -> siIdname . siGuiStuff $ si
        (h:_) -> T.unwords ((idstr <> ".") : map lpLemma (snd3 h))
  where
    idstr = pretty (siId si)
