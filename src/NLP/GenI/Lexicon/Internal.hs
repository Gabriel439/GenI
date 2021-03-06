-- GenI surface realiser
-- Copyright (C) 2005-2009 Carlos Areces and Eric Kow
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

{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
-- | Internals of lexical entry manipulation
module NLP.GenI.Lexicon.Internal where

-- import Debug.Trace -- for test stuff
import           Data.Binary
import           Data.FullList
import           Data.Function
import           Data.Generics             (Data)
import           Data.List                 (sortBy)
import           Data.Text                 (Text)
import qualified Data.Text                 as T
import           Data.Typeable             (Typeable)

import           NLP.GenI.FeatureStructure
import           NLP.GenI.GeniShow
import           NLP.GenI.GeniVal
import           NLP.GenI.Polarity.Types   (SemPols)
import           NLP.GenI.Pretty
import           NLP.GenI.Semantics

import           Control.DeepSeq

--instance Show (IO()) where
--  show _ = ""

-- | Collection of lexical entries
type Lexicon = [LexEntry]

-- | Lexical entry
data LexEntry = LexEntry
    { iword      :: FullList Text -- ^ normally just a singleton,
                                   --   useful for merging synonyms
    , ifamname   :: Text          -- ^ tree family to anchor to
    , iparams    :: [GeniVal]     -- ^ parameters (deprecrated; use the interface)
    , iinterface :: Flist GeniVal -- ^ features to unify with tree schema interface
    , ifilters   :: Flist GeniVal -- ^ features to pick out family members we want
    , iequations :: Flist GeniVal -- ^ path equations
    , isemantics :: Sem           -- ^ lexical semantics
    , isempols   :: [SemPols]     -- ^ polarities (must be same length as 'isemantics')
    }
  deriving (Eq, Data, Typeable)

-- | See also 'mkFullLexEntry'
--   This version comes with some sensible defaults.
mkLexEntry :: FullList Text   -- ^ word
            -> Text            -- ^ family name
            -> [GeniVal]       -- ^ parameters list (deprecated)
            -> Flist GeniVal   -- ^ interface (use instead of params)
            -> Flist GeniVal   -- ^ filters
            -> Flist GeniVal   -- ^ equations
            -> Sem             -- ^ semantics
            -> LexEntry
mkLexEntry word famname params interface filters equations sem =
  mkFullLexEntry word famname params interface filters equations
      sem (map noSemPols sem)
  where
   noSemPols l = replicate (length (lArgs l)) 0

-- | Variant of 'mkLexEntry' but with more control
mkFullLexEntry :: FullList Text   -- ^ word
                -> Text            -- ^ family name
                -> [GeniVal]       -- ^ parameters list (deprecated)
                -> Flist GeniVal   -- ^ interface (use instead of params)
                -> Flist GeniVal   -- ^ filters
                -> Flist GeniVal   -- ^ equations
                -> Sem             -- ^ semantics
                -> [SemPols]       -- ^ semantic polarities
                -> LexEntry
mkFullLexEntry word famname params interface filters equations sem sempols =
    LexEntry
        (sortNub word)
        famname
        params
        (sortFlist interface)
        (sortFlist filters)
        (sortFlist equations)
        sem2
        sempols2
  where
     (sem2, sempols2) = unzip $ sortBy (compareOnLiteral `on` fst) (zip sem sempols)

instance DescendGeniVal LexEntry where
  descendGeniVal s i =
    i { iinterface  = descendGeniVal s (iinterface i)
      , iequations  = descendGeniVal s (iequations i)
      , isemantics  = descendGeniVal s (isemantics i)
      , iparams = descendGeniVal s (iparams i) }

instance Collectable LexEntry where
  collect l = (collect $ iinterface l) . (collect $ iparams l) .
              (collect $ ifilters l) . (collect $ iequations l) .
              (collect $ isemantics l)

-- ----------------------------------------------------------------------
-- lexicon semantics
-- ----------------------------------------------------------------------

-- | An annotated GeniVal. This is for a rather old, obscure
--   variant on the polarity filtering optimisation. To account
--   for zero literal semantics, we annotate each value in the
--   semantics with a positive/negative marker.  These markers
--   are then counted up to determine with we need to insert
--   more literals into the semantics or not.  See the manual
--   on polarity filtering for more details
type PolValue = (GeniVal, Int)

-- | Separate an input lexical semantics into the actual semantics
--   and the semantic polarity entries (which aren't used very much
--   in practice, being a sort of experimental feature to solve an
--   obscure-ish technical problem)
fromLexSem :: [Literal PolValue] -> (Sem, [SemPols])
fromLexSem = unzip . map fromLexLiteral

-- | Note that by convention we ignore the polarity associated
--   with the predicate itself
fromLexLiteral :: Literal PolValue -> (Literal GeniVal, SemPols)
fromLexLiteral (Literal h pr vs) =
    (lit, pols)
  where
    lit  = Literal (fst h) (fst pr) (map fst vs)
    pols = snd h : map snd vs

-- ----------------------------------------------------------------------
-- converting to text
-- ----------------------------------------------------------------------

-- TODO: does not support semantic polarities yet
instance GeniShow LexEntry where
    geniShowText l = T.intercalate "\n"
        [ T.unwords
              [ geniShowText . mkGConst $ iword l
              , ifamname l
              , paramT
              ]
        , geniKeyword "equations" $ geniShowText (iequations l)
        , geniKeyword "filters"   $ geniShowText (ifilters l)
        , geniKeyword "semantics" $ geniShowText (isemantics l)
        ]
      where
        paramT = parens . T.unwords . concat $
            [ map geniShowText (iparams l)
            , ["!"]
            , map geniShowText (iinterface l)
            ]

instance GeniShow [LexEntry] where
    geniShowText = T.intercalate "\n\n" . map geniShowText

instance Pretty LexEntry where
    pretty = geniShowText

-- ----------------------------------------------------------------------
--
-- ----------------------------------------------------------------------

{-!
deriving instance Binary LexEntry
deriving instance NFData LexEntry
!-}

-- GENERATED START


instance Binary LexEntry where
        put (LexEntry x1 x2 x3 x4 x5 x6 x7 x8)
          = do put x1
               put x2
               put x3
               put x4
               put x5
               put x6
               put x7
               put x8
        get
          = do x1 <- get
               x2 <- get
               x3 <- get
               x4 <- get
               x5 <- get
               x6 <- get
               x7 <- get
               x8 <- get
               return (LexEntry x1 x2 x3 x4 x5 x6 x7 x8)


instance NFData LexEntry where
        rnf (LexEntry x1 x2 x3 x4 x5 x6 x7 x8)
          = rnf x1 `seq`
              rnf x2 `seq`
                rnf x3 `seq`
                  rnf x4 `seq` rnf x5 `seq` rnf x6 `seq` rnf x7 `seq` rnf x8 `seq` ()
-- GENERATED STOP
