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

\chapter{Builder}
\label{cha:Builder}

The heavy lifting of GenI, the whole chart/agenda mechanism, can be
implemented in many ways.  To make it easier to write different
algorithms for GenI and compare them, we provide a single interface
for what we call Builders.

This interface is then used called by the Geni module and by the
graphical interface.  Note that each builder has its own graphical
interface and that we do a similar thing in the graphical interface
code to make it possible to use these GUIs.  Maybe a little dose of
UML might help.  See figure \ref{fig:builderUml}.

\begin{figure}
\begin{center}
\includegraphics[scale=0.5]{images/builderUml.pdf}
\label{fig:builderUml}
\caption{Essentially what the Builder interface provides}
\end{center}
\end{figure}

\ignore{
\begin{code}
module NLP.GenI.Builder
where

import Control.Monad.State
import Data.Bits ( (.&.), (.|.), bit, xor )
import Data.List ( (\\), maximum )
import qualified Data.Map as Map
import Data.Maybe ( mapMaybe, fromMaybe  )
import qualified Data.Set as Set
import Data.Tree ( flatten )
import Prelude hiding ( init )

import NLP.GenI.Automaton (NFA, automatonPaths, automatonPathSets, numStates, numTransitions)
import NLP.GenI.Configuration
  ( getListFlagP, getFlagP, hasFlagP, Params,
    ExtraPolaritiesFlg(..), MetricsFlg(..),
    IgnoreSemanticsFlg(..), RootFeatureFlg(..),
    polarised )
import NLP.GenI.General (geniBug, BitVector, multiGroupByFM, fst3, snd3, thd3)
import NLP.GenI.Btypes
  ( ILexEntry, SemInput, Sem, Pred, showPred, showSem,
    Flist, gtype, GType(Subs, Foot),
    Collectable(collect), alphaConvertById,
    GeniVal(GConst)
  )
import NLP.GenI.Polarity  (PolResult, buildAutomaton, detectPolPaths)
import NLP.GenI.Statistics (Statistics, incrIntMetric,
                   Metric(IntMetric), updateMetrics,
                   mergeMetrics, addIntMetrics,
                   queryMetrics, queryIntMetric,
                   addMetric, emptyStats,
                   )
import NLP.GenI.Tags ( TagElem(idname,tsemantics,ttree), setTidnums, TagDerivation )
\end{code}
}

\section{The interface}

All backends provide the same essential functionality:
\begin{description}
\item [run]       calls init and stepAll and potentially wraps it with some
                  other functionality.  
\item [init]      initialise the machine from the semantics and lexical selection 
\item [step]      run a realisation step
\item [stepAll]   run all realisations steps until completion
\item [finished]  determine if realisation is finished
\item [stats]     extract various statistics from it
\item [setStats]  set the statistical information 
\item [unpack]    unpack chart results into a list of sentences
\end{description}

FIXME: need to update this comment

\begin{code}
data Builder st it pa = Builder
  { init     :: Input -> pa -> (st, Statistics)
  --
  , step     :: BuilderState st ()
  , stepAll  :: BuilderState st ()
  --
  , finished :: st -> Bool
  , unpack   :: st -> [Output]
  , partial  :: st -> [Output] }

type Output = (UninflectedSentence, Derivation)
type Derivation = TagDerivation
\end{code}

To simplify interaction with the backend, we provide a single data
structure which represents all the inputs a backend could take.

\begin{code}
data Input = 
  Input { inSemInput :: SemInput
        , inLex      :: [ILexEntry] -- ^ for the debugger
        , inCands    :: [(TagElem, BitVector)]   -- ^ tag tree
        }
\end{code}

\section{Uninflected words and sentences}

Each word of an uninflected sentence consists of a lemma and some
feature structures.

\paragraph 
A SentenceAut represents a set of sentences in the form of an automaton.
The labels of the automaton are the words of the sentence.  But note! 
``word'' in the sentence is in fact a tuple (lemma, inflectional feature
structures).  Normally, the states are defined as integers, with the
only requirement being that each one, naturally enough, is unique.

\begin{code}
type UninflectedWord        = (String, Flist)
type UninflectedSentence    = [ UninflectedWord ] 
type UninflectedDisjunction = ([String], Flist)
type SentenceAut            = NFA Int UninflectedWord 
\end{code}

\section{BuilderState}

To cleanly seperate the tracking of statistics from the core functionality of a
builder, we use a State transformer to thread a Statistics state monad inside of
our main monad.

\begin{code}
type BuilderState s a = StateT s (State Statistics) a
\end{code}

\section{Helper functions for Builders}

\subsection{Initialisation}
\label{fn:Builder:preInit}

There's a few things that need to be run before even initialising the builder.
One of these is running some of the optimisations (namely the polarity stuff),
which is made complicated by the fact that they are optional.  Another of these
to assign each of the trees with a unique ID.  Note that this has to be done
after the polarity optimisation because this optimisation may introduce new
items into the lexical selection.  Finally, we must also make sure we perform
alpha conversion so that unification does not do the wrong thing when two trees
have the same variables.

\begin{code}
preInit :: Input -> Params -> (Input, (Int,Int,Int), PolResult)
preInit input config =
 let (cand,_) = unzip $ inCands input
     seminput = inSemInput input
     --
     extraPol = fromMaybe (Map.empty) $ getFlagP ExtraPolaritiesFlg config
     rootFeat = getListFlagP RootFeatureFlg config
     -- do any optimisations
     isPol      = polarised config
     -- polarity optimisation (if enabled)
     autstuff = buildAutomaton seminput cand rootFeat extraPol
     (_, seedAut, aut, sem2) = autstuff
     autpaths = map concat $ automatonPathSets aut
     combosPol = if isPol then autpaths else [cand]
     -- chart sharing optimisation
     (cands2, pathIds) = unzip $ detectPolPaths combosPol
     -- the number of paths explored vs possible
     polcount = (length autpaths, length $ automatonPaths aut, length $ automatonPaths seedAut)
     --
     fixate ts ps = zip (map alphaConvertById $ setTidnums ts) ps
     input2 = input { inCands    = fixate cands2 pathIds
                    , inSemInput = (sem2, snd3 seminput, thd3 seminput) }
     -- note: autstuff is only useful for the graphical debugger
  in (input2, polcount, autstuff)
\end{code}

\begin{code}
-- | Equivalent to 'id' unless the input contains an empty or uninstatiated
--   semantics
unlessEmptySem :: Input -> Params -> a -> a
unlessEmptySem input config =
 let (cands,_) = unzip $ inCands input
     nullSemCands   = [ idname t | t <- cands, (null.tsemantics) t ]
     unInstSemCands = [ idname t | t <- cands, not $ Set.null $ collect (tsemantics t) Set.empty ]
     nullSemErr     = "The following trees have a null semantics: " ++ (unwords nullSemCands)
     unInstSemErr   = "The following trees have an uninstantiated semantics: " ++ (unwords unInstSemCands)
     semanticsErr   = (if null nullSemCands then "" else nullSemErr ++ "\n") ++
                      (if null unInstSemCands then "" else unInstSemErr)
  in if (null semanticsErr || hasFlagP IgnoreSemanticsFlg config)
     then id
     else error semanticsErr
\end{code}

\subsection{Running a surface realiser}

\begin{code}
-- | Performs surface realisation from an input semantics and a lexical selection.
run :: Builder st it Params -> Input -> Params -> (st, Statistics)
run builder input config =
  let -- 1 run the setup stuff
      (input2, polcount, autstuff) = preInit input config
      auts = (\(x,_,_,_) -> map snd3 x) autstuff
      -- 2 call the init stuff
      (iSt, iStats) = init builder input2 config
      -- 3 step through the whole thing
      stepAll_ = do incrCounter "pol_used_bundles" $ fst3 polcount
                    incrCounter "pol_used_paths"   $ snd3 polcount
                    incrCounter "pol_seed_paths"   $ thd3 polcount
                    incrCounter "pol_total_states" $ sum $ map numStates auts
                    incrCounter "pol_total_trans"  $ sum $ map numTransitions auts
                    incrCounter "pol_max_states"   $ maximum $ map numStates auts
                    incrCounter "pol_max_trans"    $ maximum $ map numTransitions auts
                    stepAll builder
  in runState (execStateT stepAll_ iSt) iStats
\end{code}

\subsection{Semantics and bit vectors}

\begin{code}
type SemBitMap = Map.Map Pred BitVector

-- | assign a bit vector value to each literal in the semantics
-- the resulting map can then be used to construct a bit vector
-- representation of the semantics
defineSemanticBits :: Sem -> SemBitMap
defineSemanticBits sem = Map.fromList $ zip sem bits
  where
   bits = map bit [0..] -- 0001, 0010, 0100...

semToBitVector :: SemBitMap -> Sem -> BitVector
semToBitVector bmap sem = foldr (.|.) 0 $ map doLookup sem
  where doLookup p =
         case Map.lookup p bmap of
         Nothing -> geniBug $ "predicate " ++ showPred p ++ " not found in semanticBit map"
         Just b  -> b

bitVectorToSem :: SemBitMap -> BitVector -> Sem
bitVectorToSem bmap vector =
  mapMaybe tryKey $ Map.toList bmap
  where tryKey (p,k) = if (k .&. vector == k) then Just p else Nothing
\end{code}

\subsection{Index accesibility filtering}
\label{sec:iaf}

Index accesibility filtering was described in \cite{carroll05her}.  This
is my attempt to adapt it to TAG.  This filter works as a form of delayed
substitution, basically the exact opposite of delayed adjunction.

This might be wrong, but we say that an index is originally accesible if
it is the root node's idx attribute (no atomic disjunction; atomic
disjunction is as good as a variable as far I'm concerned)

FIXME: more about this later.
FIXME: are we sure we got the atomic disjunctions right?

\begin{code}
type IafMap = Map.Map String Sem

-- | Return the literals of the semantics (in bit vector form)
--   whose accesibility depends on the given index
dependentSem :: IafMap -> String -> Sem
dependentSem iafMap x = Map.findWithDefault [] x iafMap

-- | Return the handle and arguments of a literal
literalArgs :: Pred -> [GeniVal]
literalArgs (h,_,args) = h:args

semToIafMap :: Sem -> IafMap
semToIafMap sem =
  multiGroupByFM (concatMap fromUniConst . literalArgs) sem

-- | Like 'fromGConst' but only for the non-disjoint ones: meant to be used as Maybe or List
fromUniConst :: (Monad m) => GeniVal -> m String
fromUniConst (GConst [x]) = return x
fromUniConst _ = fail "not a unique constant" -- we don't actually expect this failure msg to be used

getIdx :: Flist -> [GeniVal]
getIdx fs = [ v | (a,v) <- fs, a == "idx" ]

ts_iafFailure :: [String] -> [Pred] -> String
ts_iafFailure is sem = "index accesibility failure -" ++ (unwords is) ++ "- blocked: " ++ showSem sem

-- | Calculate the new set of accessibility/inaccesible indices, returning a
--   a tuple of accesible / inaccesible indices
recalculateAccesibility :: (IafAble a) => a -> a
recalculateAccesibility i =
  let oldAcc = iafAcc i
      newAcc = iafNewAcc i
      oldInacc = iafInacc i
      newInacc = oldInacc ++ (oldAcc \\ newAcc)
  in iafSetInacc newInacc $ iafSetAcc newAcc i

-- | Return, in bitvector form, the portion of a semantics that is inaccesible
--   from an item
iafBadSem :: (IafAble a) => IafMap -> SemBitMap
          -> BitVector -- ^ the input semantics
          -> (a -> BitVector) -- ^ the semantics of the item
          -> a -> BitVector
iafBadSem iafMap bmap sem semfn i =
  let -- the semantics we can't reach
      inaccessible = foldr (.|.) 0 $ map (semToBitVector bmap . dependentSem iafMap) $ iafInacc i
      -- the semantics we still _need_ to be able to reach
      remaining = sem `xor` (semfn i)
      -- where we're in trouble
  in inaccessible .&. remaining

class IafAble a where
  iafAcc      :: a -> [String]
  iafInacc    :: a -> [String]
  iafSetAcc   :: [String] -> a -> a
  iafSetInacc :: [String] -> a -> a
  iafNewAcc   :: a -> [String]
\end{code}

\subsection{Generate step}

\begin{code}
-- | Default implementation for the 'stepAll' function in 'Builder'
defaultStepAll :: Builder st it pa -> BuilderState st ()
defaultStepAll b =
 do s <- get
    unless (finished b s) $
      do step b
         defaultStepAll b
\end{code}

\subsection{Dispatching new chart items}
\label{sec:dispatching}

Dispatching consists of assigning a chart item to the right part of the
chart (agenda, trash, results list, etc).  This is implemented as a
series of filters which can either fail or succeed.

Counter-intuitively, success is defined as returning \verb!Nothing!.
Failure is defined as return \verb!Just!, because if a filter fails, it
has the right to modify the item for the next filter.  For example, the
top and bottom unification filter succeeds if it \emph{cannot} unify
the top and bottom features of a node.  It suceeds by putting the item
into the trash and returning Nothing.  If it \emph{can} perform top and
bottom unification, we want to return the item where the top and bottom
nodes are unified.  Failure is success, war is peace, freedom is
slavery, erase is backspace.

\begin{code}
type DispatchFilter s a = a -> s (Maybe a)

-- | Sequence two dispatch filters.
(>-->) :: (Monad s) => DispatchFilter s a -> DispatchFilter s a -> DispatchFilter s a
f >--> f2 = \x -> f x >>= maybe (return Nothing) f2

-- | A filter that always fails (i.e. no filtering)
nullFilter :: (Monad s) => DispatchFilter s a
nullFilter = return.Just

-- | If the item meets some condition, use the first filter, otherwise
--   use the second one.
condFilter :: (Monad s) => (a -> Bool)
           -> DispatchFilter s a -> DispatchFilter s a
           -> DispatchFilter s a
condFilter cond f1 f2 = \x -> if cond x then f1 x else f2 x
\end{code}

\subsection{Statistics}

\begin{code}
addCounters :: Statistics -> Statistics -> Statistics
addCounters = mergeMetrics addIntMetrics

modifyStats :: (Metric -> Metric) -> BuilderState st ()
modifyStats fn = lift $ modify $ updateMetrics fn

incrCounter :: String -> Int -> BuilderState st ()
incrCounter key n = modifyStats (incrIntMetric key n)

queryCounter :: String -> Statistics -> Maybe Int
queryCounter key s =
  case queryMetrics (queryIntMetric key) s of
  []  -> Nothing
  [c] -> Just c
  _   -> geniBug $ "More than one instance of the metric: " ++ key
\end{code}

\subsection{Command line configuration}

\begin{code}
initStats :: Params -> Statistics
initStats pa =
 let identifyMs :: [String] -> [Metric]
     identifyMs ["default"] = identifyMs defaultMetricNames
     identifyMs ms = map namedMetric ms
     metrics = identifyMs $ fromMaybe [] $ getFlagP MetricsFlg pa
 in execState (mapM addMetric metrics) emptyStats

namedMetric :: String -> Metric
-- the default case is that it's an int metric
namedMetric n = IntMetric n 0

-- Note that the strings here are command-line strings, not metric names!
defaultMetricNames :: [ String ]
defaultMetricNames = [ num_iterations, chart_size, num_comparisons ]
\end{code}

\subsection{Common counters}

These numbers allow us to keep track of how efficient our generator is
and where we are in the process (how many steps we've taken, etc)

\begin{code}
num_iterations, chart_size, num_comparisons :: String

num_iterations  = "iterations"
chart_size      = "chart_size"
num_comparisons = "comparisons"
\end{code}

\section{The null builder}

For the purposes of tracking certain statistics without interfering with the
lazy evaluation of the real builders.  For example, one we would like to be
able to do is count the number of substitution and foot nodes in the lexical
selection.  Doing so would in a real builder might cause it to walk entire
trees for ptoentially no good reason.

\begin{code}
nullBuilder :: Builder () (NullState ()) Params
nullBuilder = Builder
  { NLP.GenI.Builder.init = initNullBuilder
  , step         = return ()
  , stepAll      = return ()
  , finished     = const True
  , unpack       = return []
  , partial      = return []
  }

type NullState a = BuilderState () a

initNullBuilder ::  Input -> Params -> ((), Statistics)
initNullBuilder input config =
  let countsFor ts = (length ts, length nodes, length sn, length an)
        where nodes = concatMap (flatten.ttree) ts
              sn = [ n | n <- nodes, gtype n == Subs  ]
              an = [ n | n <- nodes, gtype n == Foot  ]
      --
      (tsem,_,_) = inSemInput input
      cands = map fst $ inCands input
      (_,_,(_,_,aut,_)) = preInit input config
      cands2 = concatMap concat $ automatonPathSets aut
      --
      countUp = do incrCounter "sem_literals"  $ length tsem
                   --
                   incrCounter "lex_subst_nodes" snl
                   incrCounter "lex_foot_nodes"  anl
                   incrCounter "lex_nodes"        nl
                   incrCounter "lex_trees"        tl
                   -- node count after polarities are taken into account
                   incrCounter "plex_subst_nodes" snl2
                   incrCounter "plex_foot_nodes"  anl2
                   incrCounter "plex_nodes"        nl2
                   incrCounter "plex_trees"        tl2
                where (tl , nl , snl , anl ) = countsFor cands
                      (tl2, nl2, snl2, anl2) = countsFor cands2
  in runState (execStateT countUp ()) (initStats config)
\end{code}


