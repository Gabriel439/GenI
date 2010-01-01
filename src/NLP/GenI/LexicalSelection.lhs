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

\chapter{Lexical selection}
\label{sec:candidate_selection}

This module performs the core of lexical selection and anchoring.

\ignore{
\begin{code}
module NLP.GenI.LexicalSelection
where

import Control.Arrow ((&&&))
import Control.Monad.Error

import Data.Function ( on )
import Data.List
import Data.List.Split ( wordsBy )
import qualified Data.Map as Map
import Data.Maybe (mapMaybe, isJust)
import Data.Tree (Tree(Node))

import System.IO.Unsafe (unsafePerformIO)


import NLP.GenI.General(filterTree, repAllNode,
    multiGroupByFM,
    geniBug,
    repNodeByNode,
    fst3,
    )
import NLP.GenI.Btypes
  (Macros, ILexEntry, Lexicon,
   replace, replaceList,
   Sem, sortSem, subsumeSem, params,
   AvPair(..),
   GNode(ganchor, gnname, gup, gdown, gaconstr, gtype, gorigin),
   GType(Subs, Other),
   isemantics, ifamname, iword, iparams, iequations,
   iinterface, ifilters,
   isempols,
   toKeys,
   showLexeme,
   pidname, pfamily, pinterface, ptype, psemantics, ptrace,
   setAnchor, setLexeme, tree, unifyFeat,
   alphaConvert,
   )
import NLP.GenI.BtypesBinary ()
import NLP.GenI.GeniVal( unify, GeniVal(gConstraints), isConst )

import NLP.GenI.Tags (Tags, TagElem, emptyTE,
             idname, ttreename,
             ttype, tsemantics, ttree, tsempols,
             tinterface, ttrace,
             )
import NLP.GenI.TreeSchemata ( Ttree(..) )
\end{code}
}

\section{Selecting candidate lemmas}

The lexical selection selects lemmas from the lexicon whose semantics
subsumes the input semantics.

\begin{code}
-- | Select and returns the set of entries from the lexicon whose semantics
--   subsumes the input semantics.
chooseLexCand :: Lexicon -> Sem -> [ILexEntry]
chooseLexCand slex tsem =
  let keys = toKeys tsem
      -- we choose candidates that match keys
      lookuplex t = Map.findWithDefault [] t slex
      cand  = concatMap lookuplex $ myEMPTY : keys
      -- and refine the selection...
      cand2 = chooseCandI tsem cand
      -- treat synonyms as a single lexical entry
      -- FIXME: disabled see mergeSynonyms for explanation
      -- cand3 = mergeSynonyms cand2
  in cand2

-- | 'chooseCandI' @sem l@ attempts to unify the semantics of @l@ with @sem@
--   If this succeeds, we use return the result(s); if it fails, we reject
--   @l@ as a lexical selection candidate.
chooseCandI :: Sem -> [ILexEntry] -> [ILexEntry]
chooseCandI tsem cand =
  let replaceLex i (sem,sub) =
        (replace sub i) { isemantics = sem }
      --
      helper :: ILexEntry -> [ILexEntry]
      helper l = if null sem then [l]
                 else map (replaceLex l) psubsem
        where psubsem = subsumeSem tsem sem
              sem = isemantics l
      --
  in nub $ concatMap helper cand
\end{code}

A semantic key is a semantic literal boiled down to predicate plus arity
(see section \ref{btypes_semantics}).

\begin{code}
-- | 'mapBySemKeys' @xs fn@ organises items (@xs@) by their semantic key
--   (retrieved by @fn@).  An item may have multiple keys.
---  This is used to organise the lexicon by its semantics.
mapBySemKeys :: (a -> Sem) -> [a] -> Map.Map String [a]
mapBySemKeys semfn xs =
  let gfn t = if (null s) then [myEMPTY] else toKeys s
              where s = semfn t
  in multiGroupByFM gfn xs
\end{code}

\fnlabel{mergeSynonyms} is a factorisation technique that uses
atomic disjunction to merge all synonyms into a single lexical
entry.  Two lexical entries are considered synonyms if their
semantics match and they point to the same tree families.

FIXME: 2006-10-11 - note that this is no longer being used,
because it breaks the case where two lexical entries differ
only by their use of path equations.  Perhaps it's worthwhile
just to add a check that the path equations match exactly.

\begin{code}
{-
mergeSynonyms :: [ILexEntry] -> [ILexEntry]
mergeSynonyms lexEntry =
  let mergeFn l1 l2 = l1 { iword = (iword l1) ++ (iword l2) }
      keyFn l = (ifamname l, isemantics l)
      synMap = foldr helper Map.empty lexEntry
        where helper x acc = Map.insertWith mergeFn (keyFn x) x acc
  in Map.elems synMap
-}
\end{code}

% --------------------------------------------------------------------
\section{Anchoring}
\label{sec:combine_macros}
% --------------------------------------------------------------------

This section of the code helps you to combined a selected lexical item with
a macro or a list of macros.  This is a process that can go fail for any
number of reasons, so we try to record the possible failures for book-keeping.

\begin{code}
data LexCombineError =
        BoringError String
      | EnrichError { eeMacro    :: Ttree GNode
                    , eeLexEntry :: ILexEntry
                    , eeLocation :: PathEqLhs }
     | OtherError (Ttree GNode) ILexEntry String

instance Error LexCombineError where
  noMsg    = strMsg "error combining items"
  strMsg s = BoringError s

instance Show LexCombineError where
 show (BoringError s)    = s
 show (OtherError t l s) = s ++ " on " ++ pfamily t ++ " (" ++ (showLexeme $ iword l) ++ ")"
 show (EnrichError t l _) = show (OtherError t l "enrichment error")
\end{code}

The first step in lexical selection is to collect all the features and
parameters that we want to combine.

\begin{code}
-- | 'combine' @macros lex@ creates the 'Tags' repository combining lexical
--   entries and un-anchored trees from the grammar. It also unifies the
--   parameters used to specialize un-anchored trees and propagates additional
--   features given in the 'ILexEntry'.
combine :: Macros -> Lexicon -> Tags
combine gram lexicon =
  let helper li = mapEither (combineOne li) macs
       where tn   = ifamname li
             macs = [ t | t <- gram, pfamily t == tn ]
  in Map.map (\e -> concatMap helper e) lexicon

mapEither :: (a -> Either l r) -> [a] -> [r]
mapEither fn = mapMaybe (\x -> either (const Nothing) Just $ fn x)
\end{code}

\begin{code}
-- | Given a lexical item, looks up the tree families for that item, and
--   anchor the item to the trees.
combineList :: Macros -> ILexEntry
            -> ([LexCombineError],[TagElem]) -- ^ any warnings, plus the results
combineList gram lexitem =
  case [ t | t <- gram, pfamily t == tn ] of
       []   -> ([BoringError $ "Family " ++ tn ++ " not found in Macros"],[])
       macs -> unzipEither $ map (combineOne lexitem) macs
  where tn = ifamname lexitem

unzipEither :: (Error e, Show b) => [Either e b] -> ([e], [b])
unzipEither es = helper ([],[]) es where
 helper accs [] = accs
 helper (eAcc, rAcc) (Left e : next)  = helper (e:eAcc,rAcc) next
 helper (eAcc, rAcc) (Right r : next) = helper (eAcc,r:rAcc) next
\end{code}

\begin{code}
-- | Combine a single tree with its lexical item to form a bonafide TagElem.
--   This process can fail, however, because of filtering or enrichement
combineOne :: ILexEntry -> Ttree GNode -> Either LexCombineError TagElem
combineOne lexRaw eRaw = -- Maybe monad
 -- trace ("\n" ++ (show wt)) $
 do let l1 = alphaConvert "-l" lexRaw
        e1 = alphaConvert "-t" eRaw
    (l,e) <- unifyParamsWithWarning (l1,e1)
             >>= unifyInterfaceUsing iinterface
             >>= unifyInterfaceUsing ifilters -- filtering
             >>= enrichWithWarning -- enrichment
    let name = concat $ intersperse ":" $ filter (not.null)
                 [ head (iword l) , pfamily e , pidname e ]
    return $ emptyTE
              { idname = name
              , ttreename = pfamily e
              , ttype = ptype e
              , ttree = setOrigin name . setLemAnchors . setAnchor (iword l) $ tree e
              , tsemantics  =
                 sortSem $ case psemantics e of
                           Nothing -> isemantics l
                           Just s  -> s
              , tsempols    = isempols l
              , tinterface  = pinterface e
              , ttrace      = ptrace e
              }
 where
  unifyParamsWithWarning (l,t) =
   -- trace ("unify params " ++ wt) $
   let lp = iparams l
       tp = params t
   in if length lp /= length tp
      then Left $ OtherError t l $ "Parameter length mismatch"
      else case unify lp tp of
             Nothing -> Left $ OtherError t l $ "Paremeter unification error"
             Just (ps2, subst) -> Right (replace subst l, t2)
                                  where t2 = (replace subst t) { params = ps2 }
  unifyInterfaceUsing ifn (l,e) =
    -- trace ("unify interface" ++ wt) $
    case unifyFeat (ifn l) (pinterface e) of
    Nothing             -> Left $ OtherError e l $ "Interface unification error"
    Just (int2, fsubst) -> Right $ (replace fsubst l, e2)
                           where e2 = (replace fsubst e) { pinterface = int2 }
  --
  enrichWithWarning (l,e) =
    -- trace ("enrich" ++ wt) $
    do e2 <- enrich l e
       return (l,e2)
\end{code}

\subsection{Enrichment}

Enrichment is a process which adds features to either the interface, an
explicitly named node or the co-anchor of a lexically selected tree.  The
enrichement information comes from the lexicon in the form of a path equations
which specify
\begin{enumerate}
\item the location
\item top or bottom
\item the attribute
\item what value to associate with it
\end{enumerate}

The conventions taken by GenI for path equations are:

\begin{tabular}{|l|p{8cm}|}
\hline
\verb!interface.foo=bar! &
\fs{foo=bar} is unified into the interface (not the tree) \\
\hline
\verb!anchor.bot.foo=bar! &
\fs{foo=bar} is unified into the bottom feature of the node
which is marked anchor.  \\
\hline
\verb!toto.top.foo=bar! &
\fs{foo=bar} is unified into the top feature of node named toto \\
\hline
\verb!toto.bot.foo=bar! &
\fs{foo=bar} is unified into the bot feature of node named toto \\
\hline
\verb!anchor.foo=bar! &
same as \verb!anchor.bot.foo=bar!  \\
\hline
\verb!anc.whatever...! &
same as \verb!anchor.whatever...!  \\
\hline
\verb!top.foo=bar! &
same as \verb!anchor.top.foo=bar!  \\
\hline
\verb!bot.foo=bar! &
same as \verb!anchor.bot.foo=bar!  \\
\hline
\verb!foo=bar! &
same as \verb!anchor.bot.foo=bar!  \\
\hline
\verb!toto.foo=bar! &
same as \verb!toto.top.foo=bar! (creates a warning) \\
\hline
\end{tabular}

\begin{code}
-- | (node, top, att) (node is Nothing if anchor)
type PathEqLhs  = (String, Bool, String)
type PathEqPair = (PathEqLhs, GeniVal)

enrich :: ILexEntry -> Ttree GNode -> Either LexCombineError (Ttree GNode)
enrich l t =
 do -- separate into interface/anchor/named
    let (intE, namedE) = lexEquations l
    -- enrich the interface and everything else
    t2 <- foldM enrichInterface t intE
    -- enrich everything else
    foldM (enrichBy l) t2 namedE
 where
  toAvPair ((_,_,a),v) = AvPair a v
  enrichInterface tx en =
    do (i2, isubs) <- unifyFeat [toAvPair en] (pinterface tx)
         `catchError` (\_ -> throwError $ ifaceEnrichErr en)
       return $ (replace isubs tx) { pinterface = i2 }
  ifaceEnrichErr (loc,_) = EnrichError
    { eeMacro    = t
    , eeLexEntry = l
    , eeLocation = loc }

enrichBy :: ILexEntry -- ^ lexeme (for debugging info)
         -> Ttree GNode
         -> (PathEqLhs, GeniVal) -- ^ enrichment eq
         -> Either LexCombineError (Ttree GNode)
enrichBy lexEntry t (eqLhs, eqVal) =
 case seekCoanchor eqName t of
 Nothing -> return t -- to be robust, we accept if the node isn't there
 Just a  ->
        do let tfeat = (if eqTop then gup else gdown) a
           (newfeat, sub) <- unifyFeat [AvPair eqAtt eqVal] tfeat
                              `catchError` (\_ -> throwError enrichErr)
           let newnode = if eqTop then a {gup   = newfeat}
                                  else a {gdown = newfeat}
           return $ fixNode newnode $ replace sub t
 where
   (eqName, eqTop, eqAtt) = eqLhs
   fixNode n mt = mt { tree = repNodeByNode (matchNodeName eqName) n (tree mt) }
   enrichErr = EnrichError { eeMacro    = t
                           , eeLexEntry = lexEntry
                           , eeLocation = eqLhs }

pathEqName :: PathEqPair -> String
pathEqName = fst3.fst

missingCoanchors :: ILexEntry -> Ttree GNode -> [String]
missingCoanchors lexEntry t =
  -- list monad
  do eq <- nubBy ((==) `on` pathEqName) $ snd $ lexEquations lexEntry
     let name = pathEqName eq
     case seekCoanchor name t of
       Nothing -> [name]
       Just _  -> []

-- | Split a lex entry's path equations into interface enrichement equations
--   or (co-)anchor modifiers
lexEquations :: ILexEntry -> ([PathEqPair], [PathEqPair])
lexEquations =
  partition (nameIs "interface") . map parseAv . iequations
  where
   parseAv (AvPair a v) =
    case parsePathEq a of
      Left (err,peq) -> unsafePerformIO $ do putStrLn err
                                             return (peq,v)
      Right peq -> (peq, v)
   nameIs n x = pathEqName x == n

seekCoanchor :: String -> Ttree GNode -> Maybe GNode
seekCoanchor eqName t =
 case filterTree (matchNodeName eqName) (tree t) of
 [a] -> Just a
 []  -> Nothing
 _   -> geniBug $ "Tree with multiple matches in enrichBy. " ++
                  "\nTree: " ++ pidname t ++ "\nFamily: " ++ pfamily t ++
                  "\nMatching on: " ++ eqName

matchNodeName :: String -> GNode -> Bool
matchNodeName "anchor" = ganchor
matchNodeName n        = (== n) . gnname

-- | Parse a path equation using the GenI conventions
--   This always succeeds, but can return @Just warning@
--   if anything anomalous comes up
parsePathEq :: String -> Either (String,PathEqLhs) (PathEqLhs)
parsePathEq e =
  case wordsBy (== '.') e of
  (n:"top":r) -> Right (n, True, rejoin r)
  (n:"bot":r) -> Right (n, False, rejoin r)
  ("top":r) -> Right ("anchor", True, rejoin r)
  ("bot":r) -> Right ("anchor", False, rejoin r)
  ("anc":r) -> parsePathEq $ rejoin $ "anchor":r
  ("anchor":r)    -> Right ("anchor", False, rejoin r)
  ("interface":r) -> Right ("interface", False, rejoin r)
  (n:r) -> Left (err, (n, True, rejoin r))
           where err = "Warning: Interpreting path equation " ++ e ++
                       " as applying to top of " ++ n ++ "."
  _ -> Left (err, ("", True, e))
       where err = "Warning: could not interpret path equation " ++ e
 where
  rejoin = concat . intersperse "."
\end{code}

\subsection{Lemanchor mechanism}

One problem in building reversible grammars is the treatment of co-anchors.
In the French language, for example, we have some structures like
\natlang{C'est Jean qui regarde Marie}
\natlang{It is John who looks at Mary}

One might be tempted to hard code the ce (it) and the être (is) into the tree
for regarder (look at), something like \texttt{s(ce, être, n$\downarrow$, qui,
v(regarder), n$\downarrow$)}.  Indeed, this would work just fine for
generation, but not for parsing.  When you parse, you would encounter inflected
forms for these items for example \natlang{c'} for \natlang{ce} or
\natlang{sont} or \natlang{est} for \natlang{être}.  Hard-coding the \natlang{ce}
into such trees would break parsing.

To work around this, we propose a mechanism to have our co-anchors and parsing
too. Co-anchors that are susceptible to morphological variation should be
\begin{itemize}
\item marked in a substitution site (this is to keep parsers happy)
\item have a feature \texttt{bot.lemanchor:foo} where foo is the
      coanchor you want
\end{itemize}

GenI will convert these into non-substitution sites with a lexical item
leaf node.

\begin{code}
setLemAnchors :: Tree GNode -> Tree GNode
setLemAnchors t =
 repAllNode fn filt t
 where
  filt (Node a []) = gtype a == Subs && (isJust. lemAnchor) a
  filt _ = False
  fn (Node x k) = setLexeme (lemAnchorMaybeFake x) $
                    Node (x { gtype = Other, gaconstr = False }) k
  --
  lemAnchorMaybeFake :: GNode -> [String]
  lemAnchorMaybeFake n =
    case lemAnchor n of
    Nothing -> ["ERR_UNSET_LEMMANCHOR"]
    Just l  -> l
  lemAnchor :: GNode -> Maybe [String]
  lemAnchor n =
    case [ v | AvPair a v <- gdown n, a == _lemanchor ] of
    [l] | isConst l -> gConstraints l
    _               -> Nothing

_lemanchor :: String
_lemanchor = "lemanchor"
\end{code}

\subsection{Node origins}

After lexical selection, we label each tree node with its origin, most
likely the name and id of its elementary tree.  This is useful for
building derivation trees

\begin{code}
setOrigin :: String -> Tree GNode -> Tree GNode
setOrigin t = fmap (\g -> g { gorigin = t })
\end{code}

% ----------------------------------------------------------------------
\section{Helper functions}
% ----------------------------------------------------------------------

\begin{code}
compressLexCombineErrors :: [LexCombineError] -> [(Int, LexCombineError)]
compressLexCombineErrors = map (length &&& head) . groupBy h
 where
  h (EnrichError m1 l1 _) (EnrichError m2 l2 _) = pfamily m1 == pfamily m2 &&
                                                  iword l1 == iword l2
  h _ _ = False

myEMPTY :: String
myEMPTY = "MYEMPTY"
\end{code}
