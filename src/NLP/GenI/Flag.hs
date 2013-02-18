{-# LANGUAGE DeriveDataTypeable        #-}
{-# LANGUAGE ExistentialQuantification #-}
-- GenI surface realiser
-- Copyright (C) 2009 Eric Kow
--
-- This module can be treated as public domain

-- | Internal representation of GenI configuration options, typically
--   passed in through the command line or via the GUI.
--
--   We don't yet use the record based approach, or something like
--   cmdargs because our use case involves
--
--   * sharing lots of options between different programs
--     (batch processing, gui, server)
--
--   * supporting library users who want to build GenI-like applications
--     that share a good chunk of our flag set, and add configuration
--     options of their own.
--
--   What we have is fairly clunky, but it seems to be quite
--   flexible for that need.
module NLP.GenI.Flag where

import           Data.List                 (find)
import           Data.Maybe                (catMaybes, fromJust, fromMaybe)
import qualified Data.Set                  as Set
import           Data.Text                 (Text)
import           Data.Typeable

import           NLP.GenI.FeatureStructure (Flist)
import           NLP.GenI.GeniVal          (GeniVal)
import           NLP.GenI.Polarity.Types

-- ----------------------------------------------------------------------
-- configuration stuff
-- this stuff really belongs in NLP.GenI.Configuration but we move it here
-- to avoid an import cycle (sigh)
-- ----------------------------------------------------------------------

-- | Requested optimisations
--
--   At the time of this writing (2012-08-21), this is fairly sparse as
--   a lot of proposed optimisations have just been absorbed into GenI
--   as mandatory things.
data Optimisation = PolOpts       -- ^ all polarity-related   optimisations
                  | AdjOpts       -- ^ all adjunction-related optimisations
                  | Polarised     -- ^ polarity filtering
                  | NoConstraints -- ^ ignore literal constraints (pessimisation?)
  deriving (Show,Eq,Typeable)

-- | A test suite and any test cases within that we want to pick out
type Instruction = (FilePath, Maybe [Text])

-- | The tree assembly algorithm we want to use
data BuilderType = SimpleBuilder | SimpleOnePhaseBuilder
     deriving (Eq, Typeable)

-- | What kind of elementary trees we're getting.  The typical use case is
--   to provide tree schemata with 'GeniHand' (which then get anchored into
--   the lexicon to give us elmentary trees).  You can also have precompiled
--   trees hardcoded into your GenI-like program, or read preanchored
--   elementary trees from somewhere else.
data GrammarType = GeniHand    -- ^ geni's text format
                 | PreCompiled -- ^ built into geni, no parsing needed
                 | PreAnchored -- ^ lexical selection already done
     deriving (Show, Eq, Typeable)

defaultGrammarType :: GrammarType
defaultGrammarType = GeniHand

getGrammarType :: [Flag] -> GrammarType
getGrammarType = fromMaybe defaultGrammarType . getFlag GrammarTypeFlg

instance Show BuilderType where
  show SimpleBuilder         = "simple-2p"
  show SimpleOnePhaseBuilder = "simple-1p"


-- |
hasOpt :: Optimisation -> [Flag] -> Bool
hasOpt o p = maybe False (elem o) $ getFlag OptimisationsFlg p

-- ----------------------------------------------------------------------
-- flag core
-- ----------------------------------------------------------------------

{- |
Flags are GenI's internal representation of command line arguments.  We
use phantom existential types (?) for representing GenI flags.  This
makes it simpler to do things such as ``get the value of the MacrosFlg''
whilst preserving type safety (we always know that MacrosFlg is
associated with String).  The alternative would be writing getters and
setters for each flag, and that gets really boring after a while.
-}
data Flag = forall f x . (Eq f, Typeable f, Typeable x) =>
     Flag (x -> f) x deriving (Typeable)

{-
instance Show Flag where
 show (Flag f x) = "Flag " ++ show (f x)
-}

instance Eq Flag where
 (Flag f1 x1) == (Flag f2 x2)
   | (typeOf f1 == typeOf f2) && (typeOf x1 == typeOf x2) =
       (fromJust . cast . f1 $ x1) == (f2 x2)
   | otherwise = False

isFlag :: (Typeable f, Typeable x) => (x -> f) -> Flag -> Bool
isFlag f1 (Flag f2 _) = typeOf f1 == typeOf f2

hasFlag :: (Typeable f, Typeable x) => (x -> f) -> [Flag] -> Bool
hasFlag = any . isFlag

deleteFlag :: (Typeable f, Typeable x) => (x -> f) -> [Flag] -> [Flag]
deleteFlag f = filter (not.(isFlag f))

-- | This only has an effect if the flag is set
modifyFlag :: (Eq f, Typeable f, Typeable x) => (x -> f) -> (x -> x) -> [Flag] -> [Flag]
modifyFlag f m fs =
  case getFlag f fs of
    Nothing -> fs
    Just v  -> setFlag f (m v) fs

setFlag :: (Eq f, Typeable f, Typeable x) => (x -> f) -> x -> [Flag] -> [Flag]
setFlag f v fs = (Flag f v) : tl where tl = deleteFlag f fs

getFlag :: (Typeable f, Typeable x)  => (x -> f) -> [Flag] -> Maybe x
getFlag f fs = do (Flag _ v) <- find (isFlag f) fs ; cast v

getAllFlags :: (Typeable f, Typeable x)  => (x -> f) -> [Flag] -> [x]
getAllFlags f fs = catMaybes [ cast v | flg@(Flag _ v) <- fs, isFlag f flg ]

getListFlag :: (Typeable f, Typeable x) => ([x] -> f) -> [Flag] -> [x]
getListFlag f = fromMaybe [] . getFlag f

-- ----------------------------------------------------------------------
-- Below are just the individual flags, which unfortunately have to be
-- defined as separate data types because of our fancy existential
-- data type code.
-- ----------------------------------------------------------------------

newtype BatchDirFlg = BatchDirFlg FilePath deriving (Eq, Typeable)
newtype DisableGuiFlg = DisableGuiFlg () deriving (Eq, Typeable)
newtype DetectPolaritiesFlg = DetectPolaritiesFlg (Set.Set PolarityAttr) deriving (Eq, Typeable)
newtype DumpDerivationFlg = DumpDerivationFlg () deriving (Eq, Typeable)
newtype EarlyDeathFlg = EarlyDeathFlg () deriving (Eq, Typeable)
newtype FromStdinFlg = FromStdinFlg () deriving (Eq, Typeable)
newtype HelpFlg = HelpFlg () deriving (Eq, Typeable)
newtype InstructionsFileFlg = InstructionsFileFlg FilePath deriving (Eq, Typeable)
newtype LexiconFlg = LexiconFlg FilePath deriving (Eq, Typeable)
newtype MacrosFlg = MacrosFlg FilePath deriving (Eq, Typeable)
newtype TracesFlg = TracesFlg FilePath deriving (Eq, Typeable)
newtype MaxStepsFlg = MaxStepsFlg Integer deriving (Eq, Typeable)
newtype MaxResultsFlg = MaxResultsFlg Integer deriving (Eq, Typeable)
newtype MetricsFlg = MetricsFlg [String] deriving (Eq, Typeable)
newtype MorphCmdFlg = MorphCmdFlg String deriving (Eq, Typeable)
newtype MorphInfoFlg = MorphInfoFlg FilePath deriving (Eq, Typeable)
newtype OptimisationsFlg = OptimisationsFlg [Optimisation] deriving (Eq, Typeable)
newtype OutputFileFlg = OutputFileFlg String deriving (Eq, Typeable)
newtype PartialFlg = PartialFlg () deriving (Eq, Typeable)
newtype RankingConstraintsFlg = RankingConstraintsFlg FilePath deriving (Eq, Typeable)
newtype RootFeatureFlg = RootFeatureFlg (Flist GeniVal) deriving (Eq, Typeable)
newtype NoLoadTestSuiteFlg = NoLoadTestSuiteFlg () deriving (Eq, Typeable)
newtype StatsFileFlg = StatsFileFlg FilePath deriving (Eq, Typeable)
newtype TestCaseFlg = TestCaseFlg Text deriving (Eq, Typeable)
newtype TestInstructionsFlg = TestInstructionsFlg [Instruction] deriving (Eq, Typeable)
newtype TestSuiteFlg = TestSuiteFlg FilePath deriving (Eq, Typeable)
newtype TimeoutFlg = TimeoutFlg Int deriving (Eq, Typeable)
newtype VerboseModeFlg = VerboseModeFlg () deriving (Eq, Typeable)
newtype VersionFlg = VersionFlg () deriving (Eq, Typeable)
newtype ViewCmdFlg = ViewCmdFlg String deriving (Eq, Typeable)
newtype BuilderFlg = BuilderFlg BuilderType deriving (Eq, Typeable)
newtype GrammarTypeFlg = GrammarTypeFlg GrammarType deriving (Eq, Typeable)
-- the WeirdFlg exists strictly to please OS X when you launch
-- GenI in an application bundle (double-click)... for some
-- reason it wants to pass an argument to -p
newtype WeirdFlg = WeirdFlg String deriving (Eq, Typeable)
