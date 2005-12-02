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

\chapter{GUI Helper} 

This module provides helper functions for building the GenI graphical
user interface

\begin{code}
module GuiHelper where
\end{code}

\ignore{
\begin{code}
import Graphics.UI.WX
import Graphics.UI.WXCore

import qualified Control.Monad as Monad 
import qualified Data.Map as Map

import Data.Array
import Data.IORef
import Data.List (intersperse, nub)
import System.Directory 
import System.Process (runProcess)

import Graphviz 
import Treeprint(graphvizShowTagElem)

import Tags (tagLeaves)
import Geni 
  ( ProgState(..) ) 
import General (snd3, slash, bugInGeni)
import Btypes 
  ( showPred, showSem, showLexeme
  , Sem)
import Tags 
  ( idname, mapBySem, emptyTE, TagElem, derivation)

import Configuration(Params(..), GrammarType(..))

import Automaton (states)
import Polarity (PolAut)
\end{code}
}

\subsection{Lexically selected items}

We have a browser for the lexically selected items.  We group the lexically
selected items by the semantics they subsume, inserting along the way some
fake trees and labels for the semantics.

The arguments \fnparam{missedSem} and \fnparam{missedLex} are used to 
indicate to the user respectively if any bits of the input semantics
have not been accounted for, or if there have been lexically selected
items for which no tree has been found.

\begin{code}
candidateGui :: ProgState -> (Window a) -> [TagElem] -> Sem -> [String] -> IO Layout
candidateGui pst f xs missedSem missedLex = do
  p  <- panel f []      
  tb <- tagBrowserGui pst p xs "lexically selected item" "candidates"
  let warningSem = if null missedSem then ""
                   else "WARNING: no lexical selection for " ++ showSem missedSem ++ "\n"
      warningLex = if null missedLex then ""
                   else "WARNING: '" ++ (concat $ intersperse ", " missedLex) 
                        ++ "' were lexically selected, but are not anchored to"
                        ++ " any trees\n"
      warning = warningSem ++ warningLex
      items = if null warning then [ fill tb ] else [ hfill (label warning) , fill tb ]
      lay   = fill $ container p $ column 5 items
  return lay
\end{code}
      
\subsection{Polarity Automata}

A browser to see the automata constructed during the polarity optimisation
step.

\begin{code}
polarityGui :: (Window a) -> [(String,PolAut,PolAut)] -> PolAut -> IO Layout
polarityGui   f xs final = do
  let numsts a = " : " ++ (show n) ++ " states" 
                 where n = foldr (+) 0 $ map length $ states a 
      aut2  (_ , a1, a2) = [ a1, a2 ]
      autLabel (fv,a1,_) = [ fv ++ numsts a1, fv ++ " pruned" ]
      autlist = (concatMap aut2 xs) ++ [ final ] 
      labels  = (concatMap autLabel xs) ++ [ "final" ++ numsts final ]
      --
  gvRef   <- newGvRef False labels "automata"
  setGvDrawables gvRef autlist
  (lay,_) <- graphvizGui f "polarity" gvRef 
  return lay
\end{code}
      
\subsection{Derived Trees}

\fnlabel{toSentence} almost displays a TagElem as a sentence, but only
good enough for debugging needs.  The problem is that each leaf may be
an atomic disjunction. Our solution is just to display each choice and
use some delimiter to seperate them.  We also do not do any
morphological processing.

\begin{code}
toSentence :: TagElem -> String
toSentence = unwords . (map squishLeaf) . tagLeaves

squishLeaf :: ([String], a) -> String
squishLeaf = showLexeme.fst 
\end{code}

\subsection{TAG viewer and browser}

A TAG browser is a TAG viewer (see below) that groups trees by 
their semantics.

\begin{code}
tagBrowserGui :: ProgState -> (Window a) -> [TagElem] -> String -> String -> IO Layout
tagBrowserGui pst f xs tip cachedir = do 
  let semmap   = mapBySem xs
      sem      = Map.keys semmap
      --
      lookupTr k = Map.findWithDefault [] k semmap
      treesfor k = emptyTE : (lookupTr k)
      labsfor  k = ("___" ++ showPred k ++ "___") : (map fn $ lookupTr k)
                   where fn t = idname t 
      --
      trees    = concatMap treesfor sem
      labels   = concatMap labsfor  sem
      itNlabl  = zip trees labels
  (lay,_) <- tagViewerGui pst f tip cachedir itNlabl
  return lay
\end{code}
      
A TAG viewer is a graphvizGui that lets the user toggle the display
of TAG feature structures.

\begin{code}
tagViewerGui :: ProgState -> (Window a) -> String -> String -> [(TagElem,String)] 
               -> GvIO TagElem
tagViewerGui pst f tip cachedir itNlab = do
  let config = pa pst
  p <- panel f []      
  let (tagelems,labels) = unzip itNlab
  gvRef <- newGvRef False labels tip
  setGvDrawables gvRef tagelems 
  (lay,updaterFn) <- graphvizGui p cachedir gvRef 
  -- widgets
  detailsChk <- checkBox p [ text := "Show features"
                           , checked := False ]
  displayTraceBut <- button p [ text := "Display trace for" ]
  displayTraceCom <- choice p [ tooltip := "derivation tree" ]
  -- handlers
  let onDisplayTrace 
       = do gvSt <- readIORef gvRef
            s <- get displayTraceCom selection
            let tsel = gvsel gvSt
            Monad.when (boundsCheck tsel tagelems) $ do
            let tree = tagelems !! (gvsel gvSt)
                derv = extractDerivation tree
            if (boundsCheck s derv)
               then runViewTag pst (derv !! s)
               else fail $ "Gui: bounds check in onDisplayTrace\n" ++ bugInGeni
  let onDetailsChk c 
       = do isDetailed <- get c checked 
            setGvParams gvRef isDetailed 
            updaterFn 
  let selHandler gvSt = do
      let tsel = gvsel gvSt
      Monad.when (boundsCheck tsel tagelems) $ do
        let selected = tagelems !! tsel 
            subtrees = extractDerivation selected
        set displayTraceCom [ items :~ (\_ -> subtrees)
                            , selection :~ (\_ -> 0) ]
  --
  Monad.when (not $ null tagelems) $ do 
    setGvHandler gvRef (Just selHandler)
    set detailsChk [ on command := onDetailsChk detailsChk ]
    set displayTraceBut 
         [ on command := onDisplayTrace 
         , enabled    := grammarType config == XMGTools ] 
  -- pack it all in      
  let cmdBar = hfill $ row 5 
                [ dynamic $ widget detailsChk
                , dynamic $ widget displayTraceBut
                , dynamic $ widget displayTraceCom 
                ]
      lay2   = fill $ container p $ column 5 [ lay, cmdBar ] 
  return (lay2,updaterFn)
\end{code}

% --------------------------------------------------------------------
\section{Graphviz GUI}
\label{sec:graphviz_gui}
% --------------------------------------------------------------------

A general-purpose GUI for displaying a list of items graphically via
AT\&T's excellent Graphviz utility.  We have a list box where we display
all the labels the user provided.  If the user selects an entry from
this box, then the item corresponding to that label will be displayed.
See section \ref{sec:draw_item}.

\paragraph{gvRef}

We use IORef as a way to keep track of the gui state and to provide you
the possibility for modifying the contents of the GUI.  The idea is that 

\begin{enumerate}
\item you create a GvRef with newGvRef
\item you call graphvizGui and get back an updater function
\item whenever you want to modify something, you use setGvWhatever
      and call the updater function
\item if you want to react to the selection being changed,
      you should set gvhandler
\end{enumerate}

\begin{code}
data GraphvizOrder = GvoParams | GvoItems | GvoSel 
     deriving Eq
data GraphvizGuiSt a b = 
        GvSt { gvitems   :: Array Int a,
               gvparams  :: b,
               gvlabels  :: [String],
               -- tooltip for the selection box
               gvtip     :: String, 
               -- handler function to call when the selection is
               -- updated
               gvhandler :: Maybe (GraphvizGuiSt a b -> IO ()),
               gvsel     :: Int,
               gvorders  :: [GraphvizOrder] }
type GraphvizRef a b = IORef (GraphvizGuiSt a b)

newGvRef p l t =
  let st = GvSt { gvparams = p,
                  gvitems  = array (0,0) [],
                  gvlabels  = l, 
                  gvhandler = Nothing,
                  gvtip    = t,
                  gvsel    = 0,
                  gvorders = [] }
  in newIORef st

setGvSel gvref s  =
  do let fn x = x { gvsel = s,
                    gvorders = GvoSel : (gvorders x) }
     modifyIORef gvref fn 
  
setGvParams gvref c  =
  do let fn x = x { gvparams = c,
                    gvorders = GvoParams : (gvorders x) }
     modifyIORef gvref fn 

setGvDrawables gvref it =
  do let fn x = x { gvitems = array (0, length it) (zip [0..] it),
                    gvorders = GvoItems : (gvorders x) }
     modifyIORef gvref fn 

setGvDrawables2 gvref (it,lb) =
  do let fn x = x { gvlabels = lb }
     modifyIORef gvref fn 
     setGvDrawables gvref it

setGvHandler gvref h =
  do gvSt <- readIORef gvref
     modifyIORef gvref (\x -> x { gvhandler = h })
     case h of 
       Nothing -> return ()
       Just fn -> fn gvSt
\end{code}

\paragraph{graphvizGui} returns a layout (wxhaskell container) and a
function for updating the contents of this GUI.

Arguments:
\begin{enumerate}
\item f - (parent window) the GUI is provided as a panel within the parent.
          Note: we use window in the WxWidget's sense, meaning it could be
          anything as simple as a another panel, or a notebook tab.
\item glab - (gui labels) a tuple of strings (tooltip, next button text)
\item cachedir - the cache subdirectory.  We intialise this by creating a cache
          directory for images which will be generated from the results
\item gvRef - see above
\end{enumerate}

Returns: a function for updating the GUI 
(args for the updater function are itNlab and the index you want to select or
 -1 to keep the same selection)

%\begin{code}
%graphvizGui :: (GraphvizShow d) => 
%  (Window a) -> String -> GraphvizRef d Bool -> GvIO d
%type GvIO d = IO (Layout, IO ())
%graphvizGui f cachedir gvRef = do
%  initGvSt <- readIORef gvRef
%  rchoice  <- singleListBox f 
%              [items := gvlabels initGvSt,
%               tooltip := gvtip initGvSt]
%  let lay = fill $ widget rchoice
%  return (lay, return () )  
%\end{code}

\begin{code}
graphvizGui :: (GraphvizShow d) => 
  (Window a) -> String -> GraphvizRef d Bool -> GvIO d
type GvIO d = IO (Layout, IO ())
graphvizGui f cachedir gvRef = do
  initGvSt <- readIORef gvRef
  -- widgets
  p <- panel f [ fullRepaintOnResize := False ]
  split <- splitterWindow p []
  (dtBitmap,sw) <- scrolledBitmap split 
  rchoice  <- singleListBox split [tooltip := gvtip initGvSt]
  -- set handlers
  let openFn   = openImage sw dtBitmap 
  -- pack it all together
  let lay = fill $ container p $ margin 1 $ fill $ 
            vsplit split 5 200 (widget rchoice) (widget sw) 
  set p [ on closing := closeImage dtBitmap ]
  -- bind an action to rchoice
  let showItem = do createAndOpenImage cachedir p gvRef openFn
                 `catch` \e -> errorDialog f "" (show e)
  ------------------------------------------------
  -- create an updater function
  ------------------------------------------------
  let updaterFn = do 
        gvSt <- readIORef gvRef
        let orders = gvorders gvSt 
            labels = gvlabels gvSt
            sel    = gvsel    gvSt
        initCacheDir cachedir 
        Monad.when (GvoItems `elem` orders) $ 
          set rchoice [ items :~ (\_ -> labels) ]
        Monad.when (GvoSel `elem` orders) $
          set rchoice [ selection :~ (\_ -> sel) ]
        modifyIORef gvRef (\x -> x { gvorders = []})
        -- putStrLn "updaterFn called" 
        showItem 
  ------------------------------------------------
  -- enable the tree selector
  -- FIXME: not sure that this is correct
  ------------------------------------------------
  let selectAndShow = do
        -- putStrLn "selectAndShow called" 
        sel  <- get rchoice selection
        -- note: do not use setGvSel (infinite loop)
        modifyIORef gvRef (\x -> x { gvsel = sel })
        updaterFn
        gvSt <- readIORef gvRef
        -- call the handler if there is one 
        case (gvhandler gvSt) of 
          Nothing -> return ()
          Just h  -> h gvSt
  ------------------------------------------------
  set rchoice [ on select := selectAndShow ]
  -- call the updater function for the first time
  -- setGvSel gvRef 1
  updaterFn 
  -- return a layout and the updater function 
  return (lay, updaterFn)
\end{code}

\subsection{Scroll bitmap}

Bitmap with a scrollbar

\begin{code}
scrolledBitmap :: Window a -> IO(VarBitmap, ScrolledWindow ())
scrolledBitmap p = do
  dtBitmap <- variable [value := Nothing]
  sw       <- scrolledWindow p [scrollRate := sz 10 10, bgcolor := white,
                                on paint := onPaint dtBitmap,
                                fullRepaintOnResize := False ]       
  return (dtBitmap, sw)
\end{code}

\subsection{Bitmap functions}

The following helper functions were taken directly from the WxHaskell
sample code.

\begin{code}
type OpenImageFn = FilePath -> IO ()
type VarBitmap   = Var (Maybe (Bitmap ())) 

openImage :: Window a -> VarBitmap -> OpenImageFn
openImage sw vbitmap fname = do 
    -- load the new bitmap
    bm <- bitmapCreateFromFile fname  -- can fail with exception
    closeImage vbitmap
    set vbitmap [value := Just bm]
    -- reset the scrollbars 
    bmsize <- get bm size 
    set sw [virtualSize := bmsize]
    repaint sw
      `catch` \_ -> repaint sw

closeImage :: VarBitmap -> IO ()
closeImage vbitmap = do 
    mbBitmap <- swap vbitmap value Nothing
    case mbBitmap of
        Nothing -> return ()
        Just bm -> objectDelete bm

onPaint :: VarBitmap -> DC a -> b -> IO ()
onPaint vbitmap dc _ = do 
    mbBitmap <- get vbitmap value
    case mbBitmap of
      Nothing -> return () 
      Just bm -> do dcClear dc
                    drawBitmap dc bm pointZero False []
\end{code}

\subsection{Drawing stuff}
\label{sec:draw_item}

\paragraph{createAndOpenImage} Attempts to draw an image 
(or retrieve it from cache) and opens it if we succeed.  Otherwise, it
does nothing at all; the creation function will display an error message
if it fails.

\begin{code}
createAndOpenImage :: (GraphvizShow b) => 
  FilePath -> Window a -> GraphvizRef b Bool -> OpenImageFn -> IO ()
createAndOpenImage cachedir f gvref openFn = do 
  let errormsg g = "The file " ++ g ++ " was not created!\n"
                   ++ "Is graphviz installed?"
  r <- createImage cachedir f gvref 
  case r of 
    Just graphic -> do exists <- doesFileExist graphic 
                       if exists 
                          then openFn graphic
                          else fail (errormsg graphic)
    Nothing      -> return ()
\end{code}

\paragraph{createImage}
Creates a graphical visualisation for anything which can be displayed
by graphviz. Arguments: a cache directory, a WxHaskell window, and index and an
array of trees.  Returns Just filename if the index is valid or Nothing
otherwise 

\begin{code}
createImage :: (GraphvizShow b) => 
  FilePath -> Window a -> GraphvizRef b Bool -> IO (Maybe FilePath) 
createImage cachedir f gvref = do
  gvSt <- readIORef gvref
  -- putStrLn $ "creating image via graphviz"
  let drawables = gvitems  gvSt
      sel       = gvsel    gvSt
      config    = gvparams gvSt
      te = (drawables ! sel)
      b  = bounds drawables 
  dotFile <- createDotPath cachedir (show sel)
  graphicFile <-  createImagePath cachedir (show sel)
  let create = do toGraphviz config te dotFile graphicFile
                  return (Just graphicFile)
      handler err = do errorDialog f "Error calling graphviz" (show err) 
                       return Nothing
  exists <- doesFileExist graphicFile
  -- we only call graphviz if the image is not in the cache
  if (exists) 
     then return (Just graphicFile)
     else if (sel >= fst b && sel < snd b)
             then create `catch` handler 
             else return Nothing
\end{code}

\subsection{Cache directory}

We create a directory to put image files in so that we can avoid regenerating
images.  If the directory already exists, we can just delete all the files
in it.

\begin{code}
initCacheDir :: String -> IO()
initCacheDir cachesubdir = do 
  mainCacheDir <- gv_CACHEDIR
  cmainExists  <- doesDirectoryExist mainCacheDir 
  Monad.when (not cmainExists) $ createDirectory mainCacheDir 
  -- 
  let cachedir = mainCacheDir ++ slash ++ cachesubdir  
  cExists    <- doesDirectoryExist cachedir
  if (cExists)
    then do let notdot x = (x /= "." && x /= "..")
            contents <- getDirectoryContents cachedir
            olddir <- getCurrentDirectory
            setCurrentDirectory cachedir
            mapM removeFile $ filter notdot contents
            setCurrentDirectory olddir
            return ()
    else createDirectory cachedir
\end{code}

\section{Miscellaneous}
\label{sec:gui_misc}

A message panel for use by the Results gui panels \ref{sec:results_gui}.

\begin{code}
messageGui :: (Window a) -> String -> IO Layout 
messageGui f msg = do 
  p <- panel f []
  -- sw <- scrolledWindow p [scrollRate := sz 10 10 ]
  t  <- textCtrl p [ text := msg, enabled := False ]
  return (fill $ container p $ column 1 $ [ fill $ widget t ]) 
\end{code}

\begin{code}
gv_CACHEDIR :: IO String
gv_CACHEDIR = do
  home <- getHomeDirectory
  return $ home ++ slash ++ ".gvcache"

createImagePath :: String -> String -> IO String
createImagePath subdir name = do
  cdir <- gv_CACHEDIR
  return $ cdir ++ slash ++ subdir ++ slash ++ name ++ ".png"

createDotPath :: String -> String -> IO String
createDotPath subdir name = do 
  cdir <- gv_CACHEDIR
  return $ cdir ++ slash ++ subdir ++ slash ++ name ++ ".dot"
\end{code}

\paragraph{boundsCheck} makes sure that index s is in the bounds of list l.
This is useful for the various blocks of code that manipulate wxhaskell
selections.  Surely there must be some more intelligent way to deal with
this.

\begin{code}
boundsCheck s l = s >= 0 && s < length l
\end{code}

\begin{code}
instance GraphvizShow TagElem where
  graphvizShow = graphvizShowTagElem
\end{code}

\subsection{XMG Metagrammar stuff}

XMG trees are produced by the XMG metagrammar system
(\url{http://sourcesup.cru.fr/xmg/}). To debug these grammars, it is
useful, given a TAG tree, to see what its metagrammar origins are.  We
provide here an interface to the handy visualisation tool ViewTAG that
just does this.

\paragraph{extractDerivation} retrieves the names of all the
XMG trees that went to building a TagElem, including the TagElem
itself.  NB: for a tree like ``love\_Tn0Vn1'', we extract just the
Tn0Vn1 bit.

\begin{code}
extractDerivation :: TagElem -> [String]
extractDerivation te = 
  let -- strips all gorn addressing stuff
      stripGorn n = if dot `elem` n then stripGorn stripped else n
        where stripped =  (tail $ dropWhile (/= dot) n)
              dot = '.'
      deriv  = map (stripGorn.snd3) $ snd $ derivation te
  in  nub (idname te : deriv)
\end{code}

\paragraph{runViewTag} runs Yannick Parmentier's ViewTAG module, which
displays trees produced by the XMG metagrammar system.  

\begin{code}
runViewTag :: ProgState -> String -> IO ()
runViewTag pst idname =  
  do -- figure out what grammar file to use
     let params  = pa pst
         gramfile = macrosFile params
     -- extract the relevant bits of the treename
     let extractXMGName n = tail $ dropWhile (/= '_') n 
         drName = extractXMGName idname 
     -- run the viewer 
     let cmd  = viewCmd params 
         args = [gramfile, drName]
     -- run the viewer
     runProcess cmd args Nothing Nothing Nothing Nothing Nothing
     return ()
\end{code}
