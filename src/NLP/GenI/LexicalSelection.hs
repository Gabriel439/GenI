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

-- | This module performs the core of lexical selection and anchoring.
{-# LANGUAGE OverloadedStrings #-}
module NLP.GenI.LexicalSelection
where

import Control.Arrow ((***))
import Control.Monad.Maybe
import Control.Monad.Writer

import Data.Function ( on )
import Data.List
import qualified Data.Map as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing)
import Data.Tree (Tree(Node))
import qualified Data.Text as T
import Data.Text ( Text )

import Data.FullList hiding ( head, tail, (++) )
import qualified Data.FullList as FL

import NLP.GenI.General(filterTree, repAllNode,
    histogram,
    geniBug,
    repNodeByNode,
    )
import NLP.GenI.FeatureStructures (Flist, AvPair(..), unifyFeat)
import NLP.GenI.GeniVal( unify, GeniVal(gConstraints), isConst, Subst, replace, finaliseVars )

import NLP.GenI.Semantics ( subsumeSem, unifySem, Sem )
import NLP.GenI.Tags (TagElem(..),
             idname,
             )
import NLP.GenI.LexicalSelection.Types
import NLP.GenI.Lexicon ( ILexEntry(..), Lexicon, )
import NLP.GenI.TreeSchemata ( Ttree(..), SchemaTree, SchemaNode, Macros
                             , crushTreeGNode
                             , setAnchor, setLexeme, tree
                             , GNode(..), GType(..)
                             )
import NLP.GenI.Warnings

-- ----------------------------------------------------------------------
-- * Lexical selection algorithms
-- ----------------------------------------------------------------------

-- | See 'NLP.GenI.Configuration' if you want to use GenI with a custom
--   lexical selection function.
type LexicalSelector = Macros -> Lexicon -> Sem -> IO LexicalSelection

-- | The result of the lexical selection process
data LexicalSelection = LexicalSelection
      { -- | the main result: a set of elementary trees (ie. anchored trees)
        lsAnchored   :: [TagElem]
        -- | if available, lexical entries that were used to produce anchored
        --   trees (useful for identifying anchoring failure)
      , lsLexEntries :: [ILexEntry]
        -- | HINT: use 'Data.Monoid.mempty' to initialise to empty
      , lsWarnings   :: GeniWarnings
      }

-- | Performs standard GenI lexical selection as described in
--   <http://projects.haskell.org/GenI/manual/lexical-selection.html>
--
--   This is just 'defaultLexicalSelection' lifted into IO
defaultLexicalSelector :: Macros -> Lexicon -> Sem -> IO LexicalSelection
defaultLexicalSelector g l t = return (defaultLexicalSelection g l t)

-- | Helper for 'defaultLexicalSelector'
--   (Standard GenI lexical selection is actually pure)
--
--   This is just 'defaultLexicalChoice' and 'defaultAnchoring'
defaultLexicalSelection :: Macros -> Lexicon -> Sem -> LexicalSelection
defaultLexicalSelection grammar lexicon tsem =
  defaultAnchoring grammar (defaultLexicalChoice lexicon tsem) tsem

-- | @missingLexEntries ts lexs@ returns any of the lexical candidates
--   @lexs@ that were apparently not anchored succesfully.
--
--   TODO: it does this by (wrongly) checking for each lexical item
--   to see if any of the anchored trees in @ts@ have identical
--   semantics to that lexical item.  The better way to do this would
--   be to throw a subsumption check on top of items reported missing,
--   because it's possible for the trees to add semantics through
--   unification.
missingLexEntries :: [TagElem] -> [ILexEntry] -> [ILexEntry]
missingLexEntries cands = filter treeless
 where
  treeless l = isNothing $ find (\t -> tsemantics t == isemantics l) cands

-- ----------------------------------------------------------------------
-- * Selecting candidate lemmas
-- ----------------------------------------------------------------------

-- | Select and returns the set of entries from the lexicon whose semantics
--   subsumes the input semantics.
defaultLexicalChoice :: Lexicon -> Sem -> [ILexEntry]
defaultLexicalChoice slex tsem = chooseCandI tsem slex

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
        where psubsem = sem `subsumeSem` tsem
              sem = isemantics l
      --
  in nub $ concatMap helper cand

-- | `mergeSynonyms' is a factorisation technique that uses
--   atomic disjunction to merge all synonyms into a single lexical
--   entry.  Two lexical entries are considered synonyms if their
--   semantics match and they point to the same tree families.
-- 
--  FIXME: 2006-10-11 - note that this is no longer being used,
--  because it breaks the case where two lexical entries differ
--  only by their use of path equations.  Perhaps it's worthwhile
--  just to add a check that the path equations match exactly.
mergeSynonyms :: [ILexEntry] -> [ILexEntry]
mergeSynonyms lexEntry =
  let mergeFn l1 l2 = l1 { iword = (FL.++) (iword l1) (iword l2) }
      keyFn l = (ifamname l, isemantics l)
      synMap = foldr helper Map.empty lexEntry
        where helper x acc = Map.insertWith mergeFn (keyFn x) x acc
  in Map.elems synMap

-- --------------------------------------------------------------------
-- * Anchoring
-- --------------------------------------------------------------------

-- | The 'LexCombine' monad supports warnings during lexical selection
--   and also failure via Maybe
type LexCombine a = MaybeT (Writer [LexCombineError]) a

-- | Note an anchoring error
lexTell :: LexCombineError -> LexCombine ()
lexTell x = lift (tell [x])

-- | @defaultAnchoring schemata lex sem@  implements the later half of lexical
--   selection (tree anchoring and enrichement).  It assumes that @lex@ consists
--   just of the lexical items that have been selected, and tries to combine them
--   with the tree schemata.
--
--   This function may be useful if you are implementing your own lexical selection
--   functions, and you want GenI to take over after you've given it a @[ILexEntry]@
defaultAnchoring :: Macros -> [ILexEntry] -> Sem -> LexicalSelection
defaultAnchoring grammar lexCands tsem =
  LexicalSelection { lsAnchored   = cands
                   , lsLexEntries = lexCands
                   , lsWarnings   = mconcat [ lexWarnings, coanchorWarnings, errs ]
                   }
 where
  combinations  = map (combineList tsem grammar) lexCands
  cands         = concatMap snd combinations
  errs          = mkGeniWarnings . concat $ zipWith mkWarnings lexCands (map fst combinations)
  mkWarnings l  = map (LexWarning [l] . LexCombineOneSchemaFailed)
  coanchorWarnings = mkGeniWarnings $ do -- list monad
    l     <- lexCands
    let xs = filter (\p -> pfamily p == ifamname l) grammar
    (c,n) <- Map.toList . histogram $ concatMap (missingCoanchors l) xs
    return (LexWarning [l] (MissingCoanchors c n))
  lexWarnings = mkGeniWarnings $ case missingLexEntries cands lexCands of
                  [] -> []
                  xs -> [LexWarning xs LexCombineAllSchemataFailed]


-- ----------------------------------------------------------------------
-- ** Combination
-- ----------------------------------------------------------------------

-- | Given a lexical item, looks up the tree families for that item, and
--   anchor the item to the trees.
combineList :: Sem -> Macros -> ILexEntry
            -> ([LexCombineError],[TagElem]) -- ^ any warnings, plus the results
combineList tsem gram lexitem =
  case [ t | t <- gram, pfamily t == tn ] of
       []   -> ([FamilyNotFoundError tn],[])
       macs -> squish . swap . unzip $ map (\m -> runWriter . runMaybeT $ combineOne tsem lexitem m) macs
  where
   tn = ifamname lexitem
   swap (x,y) = (y,x)
   squish = (compressLexCombineErrors . concat) *** (concat . catMaybes)

-- | Combine a single tree with its lexical item to form a bonafide TagElem.
--   This process can fail, however, because of filtering or enrichement
combineOne :: Sem -> ILexEntry -> SchemaTree -> LexCombine [TagElem]
combineOne tsem lexRaw eRaw = -- Maybe monad
 -- trace ("\n" ++ (show wt)) $
 do let l1 = finaliseVars "-l" lexRaw
        e1 = finaliseVars "-t" eRaw
    (l,e) <- unifyParamsWithWarning (l1,e1)
             >>= unifyInterfaceUsing iinterface
             >>= unifyInterfaceUsing ifilters -- filtering
             >>= enrichWithWarning -- enrichment
    tree2 <- case crushTreeGNode (tree e) of
               Nothing -> do lexTell (SchemaError [e] (StringError "Could not flatten disjunction"))
                             fail ""
               Just x  -> return x
    let name = concat $ intersperse ":" $ filter (not.null)
                 [ FL.head (iword l) , pfamily e , pidname e ]
        template = TE
              { idname = name
              , ttreename = pfamily e
              , tidnum    = -1 -- provisional id
              , ttype = ptype e
              , ttree = setOrigin name . setLemAnchors . setAnchor (iword l) $ tree2
              , tsemantics  = []
              , tsempols    = isempols l
              , tpolarities = Map.empty
              , tinterface  = pinterface e
              , ttrace      = ptrace e
              }
    semUnifications <- case unifySem (isemantics l) (fromMaybe [] $ psemantics e) of
                         [] -> do lexTell (SchemaError [e] (StringError "could not unify lemma and schema semantics"))
                                  fail ""
                         xs -> return xs
    return $ concatMap (finaliseSemantics template) semUnifications
 where
  finaliseSemantics template (sem,sub) =
    do (sem2,sub2) <- sem `subsumeSem` replace sub tsem
       return $ replace sub2 $ template { tsemantics = sem2 }
  unifyParamsWithWarning (l,t) =
   -- trace ("unify params " ++ wt) $
   let lp = iparams l
       tp = params t
   in if length lp /= length tp
      then do lexTell (SchemaError [t] (StringError "Parameter length mismatch"))
              fail ""
      else case unify lp tp of
             Nothing -> do lexTell (SchemaError [t] (StringError "Parameter unification error"))
                           fail ""
             Just (ps2, subst) -> return (replace subst l, t2)
                                  where t2 = (replace subst t) { params = ps2 }
  unifyInterfaceUsing ifn (l,e) =
    -- trace ("unify interface" ++ wt) $
    case unifyFeat (ifn l) (pinterface e) of
    Nothing             -> do lexTell (SchemaError [e] (StringError "Interface unification error"))
                              fail ""
    Just (int2, fsubst) -> return (replace fsubst l, e2)
                           where e2 = (replace fsubst e) { pinterface = int2 }
  --
  enrichWithWarning (l,e) =
    -- trace ("enrich" ++ wt) $
    do e2 <- enrich l e
       return (l,e2)

-- ----------------------------------------------------------------------
-- ** Enrichment
-- ----------------------------------------------------------------------

-- | See <http://projects.haskell.org/manual/lexical-selection>
--   on enrichement
enrich :: ILexEntry -> SchemaTree -> LexCombine SchemaTree
enrich l t =
 do -- separate into interface/anchor/named
    (intE, namedE) <- lift $ lexEquations l
    -- enrich the interface and everything else
    t2 <- foldM enrichInterface t intE
    -- enrich everything else
    foldM enrichBy t2 namedE
 where
  enrichInterface tx en =
    case unifyFeat [en] (pinterface tx) of
      Nothing -> lexTell (ifaceEnrichErr en) >> fail ""
      Just (i2, isubs) -> return $ (replace isubs tx) { pinterface = i2 }
  ifaceEnrichErr (AvPair loc _) = SchemaError [t] (EnrichError (PeqInterface loc))

-- *** 'enrich' helpers

-- | Helper for 'enrich' (enrich by single path equation)
enrichBy :: SchemaTree
         -> PathEqPair
         -> LexCombine SchemaTree
enrichBy t eq@(eqLhs, _) =
  case maybeEnrichBy t eq of
    Nothing -> lexTell enrichErr >> return t
    Just (t2,_) -> return t2
 where
  enrichErr = SchemaError [t] (EnrichError (PeqJust eqLhs))

-- | Helper for 'enrichBy'
maybeEnrichBy :: SchemaTree
              -> PathEqPair
              -> Maybe (SchemaTree, Subst)
maybeEnrichBy t (eqLhs, eqVal) = do
  node <- seekCoanchor eqLhs t
  case eqLhs of
    PeqFeat _ eqTop eqAtt -> do
      let (get, set) = case eqTop of
                         Top     -> (gup,   \n x -> n { gup = x })
                         Bottom  -> (gdown, \n x -> n { gdown = x})
      (fs, sub) <- enrichFeat (AvPair eqAtt eqVal) (get node)
      let t2 = fixNode (set node fs) (replace sub t)
      return (t2, sub)
    PeqLex _ -> do
       vs <- gConstraints eqVal
       let node2 = node { glexeme = map T.unpack (FL.fromFL vs) }
           t2    = fixNode node2 t
       return (t2, Map.empty)
 where
  fixNode n mt = mt { tree = repNodeByNode (matchNodeName eqLhs) n (tree mt) }

-- | @enrichFeat av fs@ attempts to unify @av@ with @fs@
--
--   Note here that @fs@ is an @Flist [GeniVal]@ rather than the usual
--   @Flist GeniVal@ you may expect.  This is because it comes from
--   'SchemaTree' which allows non-atomic disjunctions of @GeniVal@
--   which have to be flatten down to at most atomic disjunctions once
--   lexical selection is complete.
enrichFeat :: AvPair GeniVal -> Flist [GeniVal] -> Maybe (Flist [GeniVal], Subst)
enrichFeat (AvPair a v) fs =
  case span (\x -> avAtt x < a) fs of
    (before,here:after) | avMatch here ->
      do let (AvPair _ fv) = here
         (v2,sub) <- unify fv (replicate (length fv) v)
         let av2 = AvPair a v2
             fs2 = replace sub before ++ (av2 : replace sub after)
         return (fs2, sub)
    (before,after) ->
      let av2 = AvPair a [v]
          fs2 = before ++ (av2 : after) in  Just (fs2, Map.empty)
  where
   avMatch (AvPair fa _) = fa == a

-- | @missingCoanchors l t@ returns the list of coanchor node names from @l@
--   that were not found in @t@
missingCoanchors :: ILexEntry -> SchemaTree -> [String]
missingCoanchors lexEntry t =
   [ name eqLhs | eqLhs <- nubBy ((==) `on` name) equations, missing eqLhs ]
 where
   equations = map fst . snd . fst . runWriter $ lexEquations lexEntry
   name (PeqFeat n _ _) = n
   name (PeqLex  n)     = n
   missing eqLhs = isNothing (seekCoanchor eqLhs t)

-- | Split a lex entry's path equations into interface enrichement equations
--   or (co-)anchor modifiers
lexEquations :: ILexEntry -> Writer [LexCombineError] ([AvPair GeniVal],[PathEqPair])
lexEquations =
  fmap myPartition . mapM parseAv . iequations
  where
   myPartition xs = ( [ AvPair a v | (PeqInterface a, v) <- xs ]
                    , [ (n,v)      | (PeqJust n, v)      <- xs ] )
   parseAv (AvPair a v) = fmap (\a2 -> (a2,v)) (parsePathEq a)

-- | @seekCoanchor lhs t@ returns @Just node@ if @t@ contains exactly one
--   node that can be identified by @lhs@, @Nothing@ if it contains none.
--
--   It crashes if there is more than one such node, because this should
--   have been caught earlier by GenI.
seekCoanchor :: NodePathEqLhs -> SchemaTree -> Maybe SchemaNode
seekCoanchor eqLhs t =
 case filterTree (matchNodeName eqLhs) (tree t) of
 [a] -> Just a
 []  -> Nothing
 _   -> geniBug $ "Tree with multiple matches in enrichBy. " ++
                  "\nTree: " ++ pidname t ++ "\nFamily: " ++ pfamily t ++
                  "\nMatching on: " ++ showPathEqLhs (PeqJust eqLhs)

-- | @matchNodeName lhs n@ is @True@ if the @lhs@ refers to the node @n@
matchNodeName :: NodePathEqLhs -> SchemaNode -> Bool
matchNodeName (PeqFeat n _ _) = matchNodeNameHelper n
matchNodeName (PeqLex n)      = matchNodeNameHelper n

-- | @matchNodeNameHelper@ recognises “anchor“ by convention; otherwise,
--   it does a name match
matchNodeNameHelper :: String -> SchemaNode -> Bool
matchNodeNameHelper "anchor" = ganchor
matchNodeNameHelper n        = (== n) . gnname

-- ----------------------------------------------------------------------
-- ** Lemanchor mechanism
-- ----------------------------------------------------------------------

-- | The lemanchor mechanism is described in
--   <http://projects.haskell.org/manual/lexical-selection>
setLemAnchors :: Tree (GNode GeniVal) -> Tree (GNode GeniVal)
setLemAnchors t =
 repAllNode fn filt t
 where
  filt (Node a []) = gtype a == Subs && (isJust. lemAnchor) a
  filt _ = False
  fn (Node x k) = setLexeme (lemAnchorMaybeFake x) $
                    Node (x { gtype = Other, gaconstr = False }) k
  --
  lemAnchorMaybeFake :: GNode GeniVal -> [String]
  lemAnchorMaybeFake n =
    case lemAnchor n of
    Nothing -> ["ERR_UNSET_LEMMANCHOR"]
    Just l  -> map T.unpack l
  lemAnchor :: GNode GeniVal -> Maybe [Text]
  lemAnchor n =
    case [ v | AvPair a v <- gup n, a == _lemanchor ] of
    [l] | isConst l -> fromFL `fmap` (gConstraints l)
    _               -> Nothing

-- | The name of the lemanchor attribute (by convention; see source)
_lemanchor :: Text
_lemanchor = "lemanchor"

-- | @setOrigin n t@ marks the nodes in @t@ as having come from
--   a tree named @n@
setOrigin :: String -> Tree (GNode v) -> Tree (GNode v)
setOrigin t = fmap (\g -> g { gorigin = t })
