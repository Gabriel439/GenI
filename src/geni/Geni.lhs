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

\chapter{Geni}

Geni is the interface between the front and backends of the generator. The GUI
and the console interface both talk to this module, and in turn, this module
talks to the input file parsers and the surface realisation engine.  This
module also does lexical selection and anchoring because these processes might
involve some messy IO performance tricks.

\begin{code}
module Geni (State(..), PState, GeniResults(..), 
             showRealisations, groupAndCount,
             initGeni, customGeni, runGeni, 
             runLexSelection, buildAutomaton, runMorph,
             loadGrammar, 
             loadTargetSem, loadTargetSemStr,
             combine)
where
\end{code}

\ignore{
\begin{code}
import Data.Char (toLower)
import Data.FiniteMap
import Data.IORef (IORef, readIORef, newIORef, modifyIORef)
import Data.List (intersect, intersperse, sort, nub, group)
import Data.Maybe (isNothing)
import Data.Tree

import System (ExitCode(ExitSuccess), 
               exitWith, getArgs)
import System.IO(hFlush, stdout)
import System.Mem

import Control.Monad (when)
import CPUTime (getCPUTime)

import Bfuncs (Macros, MTtree, ILexEntry, Lexicon, Sem, SemInput,
               GNode, GType(Subs), Flist,
               isemantics, ifamname, icategory, iword, iparams, ipfeat,
               iprecedence, icontrol,
               gnname, gtype, gaconstr, gup, gdown, toKeys,
               sortSem, subsumeSem, params, 
               substSem, substFlist', substFlist, substTree, showPairs,
               pidname, pfeat, ptype, 
               ptpolarities, 
               setLexeme, tree, unifyFeat,
               groupByFM, multiGroupByFM)

import Tags (Tags, TagElem, emptyTE, TagSite, 
             idname, tidnum, tagLeaves,
             derivation, ttype, tsemantics, ttree,
             tinterface, tpolarities, tcontrol, 
             substnodes, adjnodes, 
             appendToVars)

import Configuration(Params, defaultParams, getConf, treatArgs,
                     grammarFile, tsFile, isTestSuite, morphCmd,
                     GramParams, parseGramIndex,
                     macrosFile, lexiconFile, semlexFile, morphFile, rootCatsParam,
                     autopol, polarised, polsig, chartsharing, 
                     semfiltered, orderedadj, extrapol, footconstr)

import Mstate (Gstats, numcompar, szchart, geniter, initGstats,
               addGstats, initMState, runState, genstats,
               generate)

import Morphology
import Polarity
--import Predictors (PredictorMap, mapByPredictors, 
--                   fillPredictors, optimisePredictors)

import Lex2 (lexer)
import Mparser (mParser)
import Lparser (lexParser, semlexParser, morphParser)
import Tsparser (targetSemParser, testSuiteParser)
import ParserLib (E(..))
\end{code}
}

% --------------------------------------------------------------------
\section{State}
% --------------------------------------------------------------------

Data types for keeping track of the program state.  

\begin{description}
\item[pa] the current configuration being processed
\item[batchPa] the list of possible configurations.  This list is
               never empty.  If we are doing batch processing, 
               then its only item is pa
\item 
\end{description}

Note: if tags is non-empty, we can ignore gr and le

\begin{code}
data State = ST{pa       :: Params,
                batchPa  :: [Params], -- list of configurations
                gr       :: Macros,
                le       :: Lexicon,
                morphinf :: MorphFn,
                rootCats :: [String],
                ts       :: SemInput,
                sweights :: FiniteMap String [Int],
                tsuite   :: [(SemInput,[String])]
               }

type PState = IORef State
\end{code}

% --------------------------------------------------------------------
\section{Entry point}
% --------------------------------------------------------------------

This module mainly exports two monadic functions: an initialisation step
and a generation step.

\subsection{Initialisation step}

initGeni should be called when Geni is started.  This is typically
called from the user interface code.

\begin{code}
initGeni :: IO PState 
initGeni = do
    confGenirc <- getConf defaultParams
    args       <- getArgs
    let confArgs = treatArgs confGenirc args
    -- Initialize the general state.  
    pst <- newIORef ST{pa = head confArgs,
                       batchPa = confArgs, 
                       gr = emptyFM,
                       le = emptyFM,
                       morphinf = const Nothing,
                       ts = ([],[]),
                       sweights = emptyFM,
                       rootCats = [],
                       tsuite = [] }
    return pst 
\end{code}

\subsection{Generation step}

In the generation step, we first perform lexical selection, set up any
optimisations on the lexical choices, and then perform generation.

\paragraph{customGeni} lets you specify what function you want to use for
generation: this is useful because it lets you pass in a debugger
instead of the vanilla generator.  To run the vanilla generator, 
call this function with runGeni as the runFn argument.

\begin{code}
type GeniFn = State -> Sem -> [[TagElem]] -> IO ([TagElem], Gstats)

customGeni :: PState -> GeniFn -> IO GeniResults 
customGeni pst runFn = do 
  -- lexical selection
  mstLex   <- readIORef pst
  purecand <- runLexSelection mstLex
  -- stripping morphological predicates
  let nonmorphfn = isNothing.(morphinf mstLex)
      tsLex      = ts mstLex
      tsLex2     = (filter nonmorphfn (fst tsLex), snd tsLex)
  modifyIORef pst (\x -> x{ts = tsLex2})
  mst      <- readIORef pst
  -- force the grammar to be read before the clock
  when (-1 == (length.show.le) mst) $ exitWith ExitSuccess
  when (-1 == (length.show.gr) mst) $ exitWith ExitSuccess
  performGC
  -- force lexical selection to be run before clock
  -- when (-1 == (length.show) purecand) $ exitWith ExitSuccess
  clockBefore <- getCPUTime 
  -- do any optimisations
  let config   = pa mst
      (tsem,_) = ts mst
      extraPol    = extrapol config  
      isPol       = polarised config
  let -- polarity optimisation (if enabled)
      autstuff   = buildAutomaton purecand mst
      finalaut   = (snd.fst) autstuff
      lookupCand = lookupAndTweak (snd autstuff)
      pathsLite  = walkAutomaton finalaut 
      paths      = map (concatMap lookupCand) pathsLite 
      combosPol  = if isPol then paths else [purecand]
      -- chart sharing optimisation (if enabled)
      isChartSharing = chartsharing config
      combosChart = if isChartSharing 
                    then [ detectPolPaths combosPol ] 
                    else map defaultPolPaths combosPol 
      -- 
      combos    = combosChart
      fstGstats = initGstats
  -- do the generation
  (res, gstats') <- runFn mst tsem combos
  let gstats  = addGstats fstGstats gstats'
  -- statistics 
  let statsOpt =  if (null optAll) then "none " else optAll
                  where polkey   = "pol"
                        polplus  =    (if autopol config then "A" else "")
                                   ++ (if polsig  config then "S" else "")
                                   ++ (if isChartSharing then "C" else "")
                        --
                        adjplus  =    (if semfiltered config then "S" else "")
                                   ++ (if orderedadj  config then "O" else "")
                                   ++ (if footconstr  config then "F" else "")
                        --
                        optAll   = optPol ++ optAdj
                        optPol   = if isPol     
                                   then (if null polplus then polkey else polkey ++ ":" ++ polplus) 
                                   else "" 
                        optAdj   = if null adjplus then "" else " adj:" ++ adjplus
      statsAut     = if isPol then show $ length combosPol else ""
      ambiguityStr = show $ calculateTreeCombos purecand 
  -- pack up the results
  let results = GR { -- grCand     = purecand,
                     -- grAuts = auts,
                     -- grCombos   = combos,
                     grDerived  = res, 
                     grSentences = [],
                     grOptStr   = (statsOpt, showLitePm extraPol),
                     grAutPaths = statsAut,
                     grTimeStr  = "",
                     grAmbiguity = ambiguityStr,
                     grStats    = gstats }
  -- note: we have to do something with the results to force evaluation
  -- of the generator (for timing)
  when (length (show results) == 0) $ exitWith ExitSuccess
  clockAfter  <- getCPUTime 
  let timediff = (fromInteger $ clockAfter - clockBefore) / 1000000000
      statsTime = (show $ timediff) 
  when (length statsTime == 0) $ exitWith ExitSuccess
  -- morphology 
  let uninflected = map tagLeaves res
  sentences <- runMorph pst uninflected
  -- final rensults 
  return (results { grSentences = map (map toLower) sentences,
                    grTimeStr  = statsTime })
\end{code}

% --------------------------------------------------------------------
\section{Lexical selection}
\label{sec:candidate_selection} \label{sec:lexical_selecetion} \label{par:lexSelection}
% --------------------------------------------------------------------

\paragraph{runLexSelection} determines which candidates trees which
will be used to generate the current target semantics.  

Note: we assign a tree id to each selected tree, and we append some
unique suffix (coincidentally the tree id) to each variable in each
selected tree. This is to avoid nasty collisions during unification as
mentioned in section \ref{sec:fs_unification}).

\begin{code}
runLexSelection :: State -> IO [TagElem] 
runLexSelection mst = do
    let (tsem,_) = ts mst
        lexicon     = le mst
        -- select lexical items first 
        lexCand   = chooseLexCand lexicon tsem
        -- then anchor these lexical items to trees
        combiner = combineList (gr mst) 
        cand     = concatMap combiner lexCand
        -- attach any morphological information to the candidates
        morphfn  = morphinf mst
        cand2    = attachMorph morphfn tsem cand 
        -- assure unique variable names
        setnum c i = appendToVars (mksuf i) (c { tidnum = i })
        mksuf i = "-" ++ (show i)
    return $ zipWith setnum cand2 [1..]
\end{code}

\paragraph{buildAutomaton} constructs the polarity automaton from the
lexical selection.

\begin{code}
buildAutomaton :: [TagElem] -> State -> (PolResult, TagLite -> [TagElem])
type PolResult = ([(String, PolAut, PolAut)], PolAut)

buildAutomaton candRaw mst =
  let config   = pa mst
      (tsem,tres) = ts mst
      swmap    = sweights mst
      -- restrictors and extra polarities
      mergePol = plusFM_C (+)
      rootCatPref = prefixRootCat $ head $ rootCats mst
      rcatPol = if (null $ rootCats mst)
                then emptyFM
                else addToFM emptyFM rootCatPref (-1)
      extraPol = mergePol (extrapol config) $ mergePol rest rcatPol
                 where rest = declareRestrictors tres
      detect   = detectRestrictors tres
      restrict t = t { tpolarities = mergePol p r
                     } --, tinterface  = [] }
                   where p  = tpolarities t
                         r  = (detect . tinterface) t
      candRest  = map restrict candRaw 
      -- polarity detection (if needed)
      isAutoPol = autopol   config
      cand = if isAutoPol 
             then detectPols candRest
             else candRest
      -- building the automaton
      (candLite, lookupCand) = reduceTags (polsig config) cand
      auts = makePolAut candLite tsem extraPol swmap
  in (auts, lookupCand)
\end{code}

% --------------------------------------------------------------------
\subsection{Combine}
\label{sec:combine_macros}
% --------------------------------------------------------------------

combine: Given 
- the Macros and 
- a list of ILexEntry (read from the Lexicon.in file) 

it creates the Tags repository combining lexical entries and
un-anchored trees from the grammar. It also unifies the parameters
used to specialize un-anchored trees and propagates additional features
given in the ILexEntry. 

\begin{code}
combine :: Macros -> Lexicon -> Tags
\end{code}

We start by collecting all the features and parameters we want to combine.

\begin{code}
combine g lexicon =
  let helper li = map (combineOne li) macs 
                  where tn   = ifamname li
                        macs = lookupWithDefaultFM g [] tn
  in mapFM (\_ e -> concatMap helper e) lexicon 
\end{code}

\paragraph{combineList} takes a lexical item; it looks up the tree
families for that item, and anchors the item to the trees.  A simple
list of trees is returned.

\begin{code}
combineList :: Macros -> ILexEntry -> [TagElem]
combineList g lexitem = 
  let tn = ifamname lexitem
      macs = case (lookupFM g tn) of
                Just tt -> tt
                Nothing -> error ("Family " ++ tn ++ " not found in Macros")
  in map (combineOne lexitem) macs
\end{code}

\paragraph{combineOne} combines a single tree with its lexical item to
form a bonafide TagElem

\begin{code}
combineOne :: ILexEntry -> MTtree -> TagElem
combineOne lexitem e = 
   let wt = "(Word: "++ (iword lexitem) ++
            ", Family:" ++ (ifamname lexitem) ++ ")\n"
       -- lexitem stuff
       sem  = isemantics lexitem
       p    = iparams lexitem
       pf   = ipfeat lexitem
       fpf  = map fst pf
       -- tree stuff
       tp   = params e
       tpf  = pfeat e
       ftpf = map fst tpf
       -- unify the parameters
       psubst = zip tp p
       paramsUnified = substTree (Bfuncs.tree e) psubst 
       -- unify the features
       pf2  = substFlist pf  psubst
       tpf2 = substFlist tpf psubst
       (fsucc, funif, fsubst) = unifyFeat pf2 tpf2
       featsUnified = substTree paramsUnified fsubst 
       -- detect subst and adj nodes
       unified = featsUnified
       (snodes,anodes) = detectSites unified 
       -- the final result
       sol = emptyTE {
                idname = iword lexitem ++ "-" ++ icategory lexitem 
                         ++ "_" ++ pidname e,
                derivation = (0,[]),
                ttype = ptype e,
                ttree = setLexeme (iword lexitem) unified,
                substnodes = snodes,
                adjnodes   = anodes,
                tsemantics = substSem sem fsubst,
                tpolarities = ptpolarities e,
                tinterface  = funif,
                tcontrol    = icontrol lexitem
                -- tpredictors = combinePredictors e lexitem
               }        
       -- well... with error checking
       wterror s = error (s ++ " " ++ wt)
       result 
         -- if the parameters are of different length
         | (length p) /= (length tp) = wterror "Wrong number of parameters."
{-
  This check prevents us from using large families of trees with
  very different interfaces

         -- if the lex item features are not a subset of the tree features
         | intersect fpf ftpf /= fpf = error $
             "Lex entry " ++ iword lexitem 
             ++ "'s features are not a subset of"
             ++ " tree's features: "  
             ++ "\nlex:  " ++ show fpf  
             ++ "\ntree: " ++ show ftpf
-}
         -- if fs unification fails for any reason (probably a bug)
         | not fsucc = wterror "Feature unification failed."
         -- success! 
         | otherwise = sol
   in result
\end{code}

\paragraph{detectSites}: Given a tree(GNode) 
returns a list of substitution or adjunction nodes

\begin{code}
detectSites :: Tree GNode -> ([TagSite], [TagSite])
detectSites (Node a lt) =
  let next = map detectSites lt
      (snodes', anodes') = unzip next
      --
      site = [(gnname a, gup a, gdown a)]
      snodes = if (gtype a == Subs) then (site:snodes') else snodes' 
      anodes = if (gaconstr a)      then anodes' else (site:anodes')
  in (concat snodes, concat anodes)
\end{code}

% --------------------------------------------------------------------
\subsection{The selection process}
% --------------------------------------------------------------------

\paragraph{chooseLexCand} selects and returns the set of entries from
the lexicon whose semantics subsumes the input semantics. 

\begin{code}
chooseLexCand :: Lexicon -> Sem -> [ILexEntry]
chooseLexCand slex tsem = 
  let -- the initial "MYEMPTY" takes care of items with empty semantics
      keys = "MYEMPTY":(toKeys tsem)   
      -- we choose candidates that match keys
      lookuplex t = lookupWithDefaultFM slex [] t
      cand    = concatMap lookuplex keys
      -- and refine the selection... 
  in chooseCandI tsem cand
\end{code}

With a helper function, we refine the candidate selection by
instatiating the semantics, at the same time filtering those which
do not stay within the target semantics, and finally eliminating 
the duplicates.

\begin{code}
chooseCandI :: Sem -> [ILexEntry] -> [ILexEntry]
chooseCandI tsem cand =
  let substLex i sub = i { isemantics = substSem (isemantics i) sub
                         , ipfeat     = substFlist (ipfeat i)   sub  
                         , iparams    = substPar  (iparams i)   sub
                         , icontrol   = substOne (icontrol i)  sub
                         }
      substPar par sub = map (\p -> substOne p sub) par
      substOne p sub = foldl sfn p sub
                       where sfn z (x,y) = if (z == x) then y else z
      --
      helper :: ILexEntry -> [ILexEntry]
      helper le = if (null sem) then [le] else map (substLex le) psubst 
                  where psubst = subsumeSem tsem sem
                        sem = isemantics le
  in nub $ concatMap helper cand
\end{code}

\paragraph{mapBySemKeys} organises items by their semantic key.  A
semantic key is a semantic literal boiled down to predicate plus arity
(see section \ref{btypes_semantics}).  Given \texttt{xs} a list of items
and \texttt{fn} a function which retrieves the item's semantics, we
return a FiniteMap from semantic key to a list of items with that key.
An item may have multiple keys.

This is used to organise the lexicon by its semantics.

\begin{code}
mapBySemKeys :: (a -> Sem) -> [a] -> FiniteMap String [a]
mapBySemKeys semfn xs = 
  let gfn t = if (null s) then ["MYEMPTY"] else toKeys s 
              where s = semfn t
  in multiGroupByFM gfn xs
\end{code}

% --------------------------------------------------------------------
\section{Loading and parsing}
% --------------------------------------------------------------------

\subsection{Grammars}

Grammars consist of the following:
\begin{enumerate}
\item index file - which tells where the other files
      in the grammar are (relative to the grammar)
\item semantic lexicon file - semantics $\rightarrow$ lemma
\item lexicon file - lemma $\rightarrow$ families
\item macros file  - unlexicalised trees
\end{enumerate}

The generator reads these into memory and combines them into a grammar
(page \pageref{sec:combine_macros}).

\paragraph{loadGrammar} Given the pointer to the monadic state pst it
reads and parses the grammar file index; and from this information,
it reads the rest of the grammar (macros, lexicon, etc).  The Macros
and the Lexicon 

\begin{code}
loadGrammar :: PState -> IO() 
loadGrammar pst =
  do st <- readIORef pst
     --
     let config   = pa st
         filename = grammarFile config
     -- 
     putStr $ "Loading index file " ++ filename ++ "..."
     hFlush stdout
     gf <- readFile filename
     putStrLn $ "done"
     --
     let gparams = parseGramIndex filename gf
     loadMacros    pst gparams
     loadLexicon   pst gparams
     loadMorphInfo pst gparams
     modifyIORef pst (\x -> x{rootCats = rootCatsParam gparams})
\end{code}

\paragraph{loadLexicon} Given the pointer to the monadic state pst and
the parameters from a grammar index file parameters; it reads and parses
the lexicon file and the semantic lexicon.   These are then stored in
the mondad.

\begin{code}
loadLexicon :: PState -> GramParams -> IO ()
loadLexicon pst config = do 
       let lfilename = lexiconFile config
           sfilename = semlexFile config
 
       putStr $ "Loading Semantic Lexicon " ++ sfilename ++ "..."
       hFlush stdout
       sf <- readFile sfilename
       let sortlexsem l = l { isemantics = sortSem $ isemantics l }
           semmapper    = mapBySemKeys isemantics
           semparsed    = (semlexParser . lexer) sf
           semlex       = (semmapper . (map sortlexsem) . fst) semparsed
           semweights   = buildSemWeights $ snd semparsed
       putStr ((show $ length $ keysFM semlex) ++ " entries\n")

       putStr $ "Loading Lexicon " ++ lfilename ++ "..."
       hFlush stdout
       lf <- readFile lfilename 
       let (_, _, rawlex) = (lexParser . lexer) lf
           lemlex = groupByFM fn rawlex
                    where fn l = (iword l, icategory l)
       putStr ((show $ length rawlex) ++ " entries\n")

       -- combine the two lexicons
       modifyIORef pst (\x -> x{le = combineLexicon lemlex semlex,
                                sweights = semweights })
       return ()
\end{code}

\paragraph{setPrecedence} takes two lists of precedence directives
(FIXME: explained where?) and a lemma lexicon.  It returns the lemma
lexicon modified so that each item is assigned a precedence according to
its membership in the list of precedence directives.  The first list of
directives are items with tight precedence; the second list are those
with loose precedence.  In both lists, items closest to the front have
tightest precedence.  Items which are not in either the tight or loose
precedence list have default precedence.

\begin{code}
type WordCat = (String,String)
type LemmaLexicon = FiniteMap WordCat [ILexEntry] 
setPrecedence :: [[WordCat]] -> [[WordCat]] 
                 -> LemmaLexicon -> LemmaLexicon
setPrecedence tight loose lemlex =
  let start  = 0 - (length tight)
      tightp = zip [start..(-1)] tight
      loosep = zip [0..] loose
      --
      tightlex = foldr setPrecedence' lemlex   tightp
  in foldr setPrecedence' tightlex loosep

setPrecedence' :: (Int,[WordCat]) -> LemmaLexicon -> LemmaLexicon
setPrecedence' (pr,items) lemlex =
  let setpr li     = li {iprecedence = pr}
      --
      helper :: WordCat -> LemmaLexicon -> LemmaLexicon
      helper wc ll = addToFM ll wc (map setpr lems)
                     where lems = lookupWithDefaultFM ll [] wc 
  in foldr helper lemlex items
\end{code}

\paragraph{combineLexicon} merges the lemma lexicon and the semantic
lexicon into a single lexicon.  The idea is that the semantic lexicon
and the lemma lexicon both use the ILexEntry data type, but they contain
different information: the semantic lexicon has the semantics and the
parameters, whereas the lemma lexicon has everything else.  Each entry
in the semantic lexicon has a semantics and a lemma.  We look the lemma
up in the (surprise!) lemma lexicon, and copy the semantic information
into each instance.

\begin{code}
combineLexicon :: LemmaLexicon -> Lexicon -> Lexicon
combineLexicon ll sl = 
  let merge si li = li { isemantics = isemantics si
                       , iparams    = iparams si
                       , ipfeat     = sort (ipfeat li ++ ipfeat si) 
                       , icontrol   = icontrol si 
                       }
      helper si = map (merge si) lemmas
                  where wordcat = (iword si, icategory si)
                        lemmas  = lookupWithDefaultFM ll [] wordcat 
  in mapFM (\_ e -> concatMap helper e) sl 
\end{code}

\paragraph{loadMacros} Given the pointer to the monadic state pst and
the parameters from a grammar index file parameters; it reads and parses
macros file.  The macros are stored as a hashing function in the monad.

\begin{code}
loadMacros :: PState -> GramParams -> IO ()
loadMacros pst config = 
  do let filename = macrosFile config
     --
     putStr $ "Loading Macros " ++ filename ++ "..."
     hFlush stdout
     gf <- readFile filename
     let g = case ((mParser.lexer) gf) of 
                   Ok g     -> g
                   Failed g -> error g
         sizeg  = sum (map length $ eltsFM g)
     putStr $ show sizeg ++ " trees in " 
     putStr $ (show $ sizeFM g) ++ " families\n"
     modifyIORef pst (\x -> x{gr = g})
\end{code}

\paragraph{loadMorphInfo} Given the pointer to the monadic state pst and
the parameters from a grammar index file parameters; it reads and parses
the morphological information file, if available.  The results are stored
as a lookup function in the monad.

\begin{code}
loadMorphInfo :: PState -> GramParams -> IO ()
loadMorphInfo pst config = 
  do let filename = morphFile config
     when (not $ null filename ) $ do --
        putStr $ "Loading Morphological Info " ++ filename ++ "..."
        hFlush stdout
        gf <- readFile filename
        let g = (morphParser.lexer) gf
            sizeg  = length g
        putStr $ show sizeg ++ " entries\n" 
        modifyIORef pst (\x -> x{morphinf = readMorph g})
\end{code}

\subsection{Target semantics}

\paragraph{loadTargetSem} given a pointer pst to the general state st,
it access the parameters and the name of the file for the target
semantics from params.  From the params, it determines if the file
is a test suite or a target semantics.  If it is a test suite, it parses
the file as a test suite, and assigns it to the tsuite field of st;
otherwise it parses it as a target semantics and assigns it to st.

\begin{code}
loadTargetSem :: PState -> IO ()
loadTargetSem pst = do
  st <- readIORef pst
  let config   = pa st
      filename = tsFile config 
      isTsuite = isTestSuite config
  putStr $ "Loading " 
           ++ (if isTsuite then "Test Suite " else "Target Semantics ")
           ++ filename ++ "..."
  hFlush stdout
  tstr <- readFile filename
  -- helper functions for test suite stuff
  let cleanup ((sm,sr),sn) = ((flattenTargetSem sm, sort sr), sort sn)
      updateTsuite s = modifyIORef pst (\x -> x {tsuite = s2})
                       where s2 = map cleanup s
  --  
  if isTsuite
     then do let sem = (testSuiteParser . lexer) tstr
             case sem of 
               Ok s     -> updateTsuite s 
               Failed s -> fail s
     else loadTargetSemStr pst tstr
  -- in the end we just say we're done
  putStr "done\n"
\end{code}

\paragraph{loadTargetSemStr} Given a string with some semantics, it
parses the string and assigns the assigns the target semantics to the ts
field of st 

\begin{code}
loadTargetSemStr :: PState -> String -> IO ()
loadTargetSemStr pst str = 
    do putStr "Parsing Target Semantics..."
       let semi = (targetSemParser . lexer) str
       case semi of 
         Ok (s,r)   -> modifyIORef pst (\x -> x{ts = (flattenTargetSem s, 
                                                      sort r)})
         Failed s   -> fail s
       putStr "done\n"
\end{code}

\paragraph{flattenTargetSem} takes a recursively embedded target
semantics like \verb$love(me wear(you sw))$ \verb$sweater(sw)$
and converts it into a flat semantics with handles like
\verb$love(h1 me h1.3)$ \verb$wear(h1.3 you)$ $sweater(h2 sw)$

FIXME: we do not know how to handle literals with no arguments!

\begin{code}
flattenTargetSem :: [Tree (String, String)] -> Sem
flattenTargetSem trees = sortSem results
  where results  = (concat . snd . unzip) results'
        results' = zipWith fn [1..] trees 
        fn g k   = flattenTargetSem' [g] k
\end{code}

\paragraph{flattenTargetSem'} We walk the semantic tree, returning an index and
a list of predicates representing the flat semantics for the entire semantic
tree.  Normally, only the second result is interesting for you; the first
result is used for recursion, the idea being that a node's parameters is the
list of indices returned by its children.  If a child does not have any
children of its own, then its index is its string value (like \verb$john$); if
it does have children, then we return a handle for it (like \verb$h1.3.4$)

\begin{code}
flattenTargetSem' :: [Int] -> Tree (String,String) -> (String, Sem)
flattenTargetSem' _  (Node ("",pred) []) = (pred, []) 

flattenTargetSem' gorn (Node (hand,pred) kids) =
  let smooshGorn = "gh" ++ (concat $ intersperse "." $ map show gorn)
      -- recursive step
      kidGorn   = map (\x -> (x:gorn)) [1..] 
      next      = zip kidGorn kids
      nextRes   = map (\ (g,k) -> flattenTargetSem' g k) next
      (kidIndexes, kidSem) = unzip nextRes
      -- create the predicate
      handle    = if null hand then smooshGorn else hand
      result    = (handle, pred, kidIndexes)
  in (smooshGorn, result:(concat kidSem))
\end{code}

% --------------------------------------------------------------------
\section{Generation step} 
% --------------------------------------------------------------------

Actually running the generator...  Note: the only reason this is monadic
is to be compatible with the debugger GUI.  There could be some code
simplifications in order.

\begin{code}
runGeni :: GeniFn 
runGeni mst tsem combos = do
  return (runGeni' (pa mst) tsem combos) 

runGeni' :: Params -> Sem -> [[TagElem]] -> ([TagElem], Gstats)
runGeni' config tsem combos = 
  -- do the generation
  let genfn c = (res, genstats st) 
                where ist = initMState c [] tsem config
                      (res,st) = runState generate ist
      res' = map genfn combos
      addres (r,s) (r2,s2) = (r ++ r2, addGstats s s2)
  in foldr addres ([],initGstats) res'
\end{code}

\subsection{Returning results}

We provide a data structure to be used by verboseGeni for returning the results
(grDerived) along with the intermediary steps and some useful statistics.  

\begin{code}
data GeniResults = GR {
  -- optimisations and extra polarities
  grOptStr   :: (String,String),
  -- some numbers (in string form)
  grStats     :: Gstats,
  grAutPaths  :: String,
  grAmbiguity :: String,
  grTimeStr   :: String,
  -- the final results
  grDerived   :: [TagElem],
  grSentences :: [String]
} 
\end{code}

We provide a default means of displaying the results/u

\begin{code}
instance Show GeniResults where
  show gres = 
    let gstats = grStats gres 
        gopts  = grOptStr gres
        sentences = grSentences gres
    in    "Optimisations: " ++ fst gopts ++ snd gopts ++ "\n"
       ++ "\nAutomaton paths explored: " ++ (grAutPaths  gres)
       ++ "\nEst. lexical ambiguity:   " ++ (grAmbiguity gres)
       ++ "\nTotal agenda size: " ++ (show $ geniter gstats) 
       ++ "\nTotal chart size:  " ++ (show $ szchart gstats) 
       ++ "\nComparisons made:  " ++ (show $ numcompar gstats)
       ++ "\nGeneration time:  " ++ (grTimeStr gres) ++ " ms"
       ++ "\n\nRealisations:\n" ++ (showRealisations sentences)
\end{code}

\paragraph{groupAndCount} is a generic list-processing function.
It converts a list of items into a list of tuples (a,b) where 
a is an item in the list and b is the number of times a in occurs 
in the list.

\begin{code}
groupAndCount :: (Eq a, Ord a) => [a] -> [(a, Int)]
groupAndCount xs = 
  map (\x -> (head x, length x)) grouped
  where grouped = (group.sort) xs
\end{code}

\paragraph{showRealisations} shows the sentences produced by the
generator in a relatively compact form 

\begin{code}
showRealisations :: [String] -> String
showRealisations sentences =
  let sentencesGrouped = map (\ (s,c) -> s ++ count c) g
                         where g = groupAndCount sentences 
      count c = if (c > 1) 
                then " (" ++ show c ++ " instances)"
                else ""
  in if (null sentences)
     then "(none)"
     else concat $ intersperse "\n" $ sentencesGrouped
\end{code}

\paragraph{runMorph} inflects a list of sentences if a morphlogical generator
has been specified.  If not, it returns the sentences as lemmas.

\begin{code}
runMorph :: PState -> [[(String,Flist)]] -> IO [String]
runMorph pst sentences = 
  do mst <- readIORef pst
     let mcmd = morphCmd (pa mst)
     if null mcmd
        then return (map sansMorph sentences)
        else inflectSentences mcmd sentences 
\end{code}
