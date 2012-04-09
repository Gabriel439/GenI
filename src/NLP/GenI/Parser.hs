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

{-# LANGUAGE CPP, FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}
module NLP.GenI.Parser (
  -- * Test suites
  geniTestSuite, geniSemanticInput, geniTestSuiteString,
  geniDerivations,
  toSemInputString,
  -- * Trees
  geniMacros, geniTagElems,
  -- * Lexicon and morph
  geniLexicon, geniMorphInfo,
  -- * Basics
  geniFeats, geniSemantics, geniValue, geniWords,
  -- * Helpers
  geniWord, geniLanguageDef, tillEof,
  --
  parseFromFile, -- UTF-8 version
  module Text.ParserCombinators.Parsec
) where


import Control.Applicative ( (<*>), (<$>), (*>) )
import Control.Monad (liftM, when)
import Data.Text ( Text )
import qualified Data.Text as T
import qualified Data.Map  as Map
import qualified Data.Tree as T
import Text.ParserCombinators.Parsec hiding (parseFromFile)
import Text.ParserCombinators.Parsec.Language (emptyDef)
import Text.ParserCombinators.Parsec.Token (TokenParser,
    LanguageDef,
    commentLine, commentStart, commentEnd, opLetter,
    reservedOpNames, reservedNames, identLetter, identStart, 
    makeTokenParser)
import qualified Text.ParserCombinators.Parsec.Token as P
import qualified Text.ParserCombinators.Parsec.Expr  as P
import qualified System.IO.UTF8 as UTF8

import NLP.GenI.FeatureStructure ( Flist, AvPair(..), sortFlist )
import NLP.GenI.General (isGeniIdentLetter)
import NLP.GenI.GeniShow (GeniShow(geniShow))
import NLP.GenI.GeniVal ( GeniVal, mkGConst, mkGConstNone, mkGVar, mkGAnon, isAnon )
import NLP.GenI.Lexicon ( mkFullILexEntry, ILexEntry(..) )
import NLP.GenI.Pretty ( prettyStr )
import NLP.GenI.Semantics ( Literal(..), Sem, sortSem, LitConstr, SemInput )
import NLP.GenI.Tag (TagElem(..), setTidnums)
import NLP.GenI.TestSuite ( TestCase(..) )
import NLP.GenI.TreeSchema (SchemaTree, Ttree(..), Ptype(..), GNode(..), GType(..) )

import BoolExp
import Data.FullList ( FullList, Listable(..) )


-- General notes

-- reserved words
#define SEMANTICS       "semantics"
#define SENTENCE        "sentence"
#define OUTPUT          "output"
#define TRACE           "trace"
#define ANCHOR          "anchor"
#define SUBST           "subst"
#define FOOT            "foot"
#define LEX             "lex"
#define TYPE            "type"
#define ACONSTR         "aconstr"
#define INITIAL         "initial"
#define AUXILIARY       "auxiliary"
#define IDXCONSTRAINTS  "idxconstraints"
#define BEGIN           "begin"
#define END             "end"

-- Lexer

geniLanguageDef :: LanguageDef ()
geniLanguageDef = emptyDef
         { commentLine = "%"
         , commentStart = "/*"
         , commentEnd = "*/"
         , opLetter = oneOf ""
         , reservedOpNames = [""]
         , reservedNames =
             [ SEMANTICS , SENTENCE, OUTPUT, IDXCONSTRAINTS, TRACE
             , ANCHOR , SUBST , FOOT , LEX , TYPE , ACONSTR
             , INITIAL , AUXILIARY
             , BEGIN , END ]
         , identLetter = identStuff
         , identStart  = identStuff
         }
  where identStuff = satisfy isGeniIdentLetter

geniValue :: Parser GeniVal
geniValue =   ((try $ anonymous) <?> "_ or ?_")
          <|> (constants  <?> "a constant or atomic disjunction")
          <|> (variable   <?> "a variable")
  where
    question = "?"
    disjunction = geniAtomicDisjunction
    constants :: Parser GeniVal
    constants = mkGConst <$> disjunction
    variable :: Parser GeniVal
    variable =
      do symbol question
         v <- tidentifier
         mcs <- option Nothing $ (symbol "/" >> Just `liftM` disjunction)
         return (mkGVar v mcs)
    anonymous :: Parser GeniVal
    anonymous =
      do optional $ symbol question
         symbol "_"
         return mkGAnon

geniAtomicDisjunction :: Parser (FullList Text)
geniAtomicDisjunction = do
    (x:xs) <- sepBy1 (T.pack <$> atom) (symbol "|")
    return (x !: xs)
  where
    atom = looseIdentifier <|> stringLiteral

geniFancyDisjunction :: Parser [GeniVal]
geniFancyDisjunction = geniValue `sepBy1` symbol ";"

class GeniValLike v where
  geniValueLike :: Parser v

instance GeniValLike GeniVal where
  geniValueLike = geniValue

instance GeniValLike [GeniVal] where
  geniValueLike = geniFancyDisjunction

-- We make no attempt to check for / guarantee uniqueness here
-- because the same sort of format is used for things which are
-- not strictly speaking feature structures
geniFeats :: GeniValLike v => Parser (Flist v)
geniFeats = option [] $ squares $ many geniAttVal

geniAttVal :: GeniValLike v => Parser (AvPair v)
geniAttVal = do
  att <- identifierR <?> "an attribute"; colon
  val <- geniValueLike <?> "a GenI value"
  return $ AvPair (T.pack att) val

geniSemantics :: Parser Sem
geniSemantics =
  do sem <- many (geniLiteral <?> "a literal")
     return (sortSem sem)

geniLiteral :: Parser Literal
geniLiteral =
  Literal <$> (option mkGAnon handleParser <?> "a handle")
          <*> (geniValue <?> "a predicate")
          <*> (parens (many geniValue) <?> "some parameters")
  where handleParser =
          try $ do { h <- geniValue ; char ':' ; return h }

geniSemanticInput :: Parser (Sem,Flist GeniVal,[LitConstr])
geniSemanticInput =
  do keywordSemantics
     (sem,litC) <- liftM unzip $ squares $ many literalAndConstraint
     idxC       <- option [] geniIdxConstraints
     --
     let sem2     = createHandles sem
         semlitC2 = [ (s,c) | (s,c) <- zip sem2 litC, (not.null) c ]
     return (createHandles sem, idxC, semlitC2)
  where
     -- set all anonymous handles to some unique value
     -- this is to simplify checking if a result is
     -- semantically complete
     createHandles :: Sem -> Sem
     createHandles = zipWith setHandle ([1..] :: [Int])
     --
     setHandle i (Literal h pred_ par) =
       let h2 = if isAnon h
                then mkGConstNone ("genihandle" `T.append` T.pack (show i))
                else h
       in Literal h2 pred_ par
     --
     literalAndConstraint :: Parser LitConstr
     literalAndConstraint =
       do l <- geniLiteral
          t <- option [] $ squares $ many tidentifier
          return (l,t)

-- | The original string representation of the semantics (for gui)
geniSemanticInputString :: Parser String
geniSemanticInputString =
 do keywordSemantics
    s <- squaresString
    whiteSpace
    optional geniIdxConstraints
    return s

geniIdxConstraints :: Parser (Flist GeniVal)
geniIdxConstraints = keyword IDXCONSTRAINTS >> geniFeats

geniLitConstraints :: Parser (BoolExp T.Text)
geniLitConstraints =
   P.buildExpressionParser table piece
 where
   piece =  (Cond <$> tidentifier)
       <|> do { string "~"; Not `liftM` geniLitConstraints }
       <|> parens geniLitConstraints
   table = [ [ op "&" And P.AssocLeft ]
           , [ op "|" Or  P.AssocLeft ]
           ]
   op s f assoc = P.Infix (do { string s ; return f }) assoc

squaresString :: Parser String
squaresString =
 do char '['
    s <- liftM concat $ many $ (many1 $ noneOf "[]") <|> squaresString
    char ']'
    return $ "[" ++ s ++ "]"

-- the output end of things
-- displaying preformatted semantic input

data SemInputString = SemInputString String (Flist GeniVal)

instance GeniShow SemInputString where
 geniShow (SemInputString semStr idxC) =
   SEMANTICS ++ ":" ++ semStr ++ (if null idxC then "" else r)
   where r = "\n" ++ IDXCONSTRAINTS ++ ": " ++ prettyStr idxC

toSemInputString :: SemInput -> String -> SemInputString
toSemInputString (_,lc,_) s = SemInputString s lc

geniTestSuite :: Parser [TestCase]
geniTestSuite =
  tillEof (many geniTestCase)

-- | Just the String representations of the semantics
--   in the test suite
geniTestSuiteString :: Parser [String]
geniTestSuiteString =
  tillEof (many geniTestCaseString)

-- | This is only used by the script genimakesuite
geniDerivations :: Parser [TestCaseOutput]
geniDerivations = tillEof $ many geniOutput

geniTestCase :: Parser TestCase
geniTestCase =
  do name  <- option "" (identifier <?> "a test case name")
     seminput <- geniSemanticInput
     sentences <- many geniSentence
     outputs   <- many geniOutput
     return $ TestCase name "" seminput sentences outputs

-- note that the keyword is NOT optional
type TestCaseOutput = (String, Map.Map (String,String) [String])
geniOutput :: Parser TestCaseOutput
geniOutput =
 do ws <- keyword OUTPUT >> (squares geniWords)
    ds <- Map.fromList `fmap` many geniTraces
    return (ws, ds)

geniTraces :: Parser ((String,String), [String])
geniTraces =
 do keyword TRACE
    squares $ do
      k1 <- withWhite geniWord
      k2 <- withWhite geniWord
      whiteSpace >> char '!' >> whiteSpace
      traces <- sepEndBy1 geniWord whiteSpace
      return ((k1,k2), traces)

withWhite :: Parser a -> Parser a
withWhite p = p >>= (\a -> whiteSpace >> return a)

geniSentence :: Parser String
geniSentence = optional (keyword SENTENCE) >> squares geniWords

geniWords :: Parser String
geniWords =
 unwords `fmap` (sepEndBy1 geniWord whiteSpace <?> "a sentence")

geniWord :: Parser String
geniWord = many1 (noneOf "[]\v\f\t\r\n ")

-- | The original string representation of a test case semantics
--   (for gui)
geniTestCaseString :: Parser String
geniTestCaseString =
 do option "" (identifier <?> "a test case name")
    s <- geniSemanticInputString
    many geniSentence
    many geniOutput
    return s

-- ----------------------------------------------------------------------
-- Lexicon
-- ----------------------------------------------------------------------

geniLexicon :: Parser [ILexEntry]
geniLexicon = tillEof $ many1 geniLexicalEntry

geniLexicalEntry :: Parser ILexEntry
geniLexicalEntry =
  do lemmas  <- geniAtomicDisjunction <?> "a lemma (or disjunction thereof)"
     family  <- tidentifier <?> "a tree family"
     (pars, interface) <- option ([],[]) $ parens paramsParser
     equations <- option [] $ do keyword "equations"
                                 geniFeats <?> "path equations"
     filters <- option [] $ do keyword "filters"
                               geniFeats
     keywordSemantics
     (sem,pols) <- squares geniLexSemantics
     --
     return (mkFullILexEntry lemmas family pars interface filters equations sem pols)
  where
    paramsParser :: Parser ([GeniVal], Flist GeniVal)
    paramsParser = do
      pars <- many geniValue <?> "some parameters"
      interface <- option [] $ do symbol "!"
                                  many geniAttVal
      return (pars, interface)

geniLexSemantics :: Parser (Sem, [[Int]])
geniLexSemantics =
  do litpols <- many (geniLexLiteral <?> "a literal")
     return $ unzip litpols

geniLexLiteral :: Parser (Literal, [Int])
geniLexLiteral =
  do (handle, hpol) <- option (mkGAnon,0) (handleParser <?> "a handle")
     predicate  <- geniValue <?> "a predicate"
     paramsPols <- parens (many geniPolValue) <?> "some parameters"
     --
     let (pars, pols) = unzip paramsPols
         literal = Literal handle predicate pars
     return (literal, hpol:pols)
  where handleParser =
          try $ do { h <- geniPolValue; colon; return h }

geniPolValue :: Parser (GeniVal, Int)
geniPolValue =
  do p <- geniPolarity
     v <- geniValue
     return (v,p)

-- ----------------------------------------------------------------------
-- Tree schemata
-- ----------------------------------------------------------------------

geniMacros :: Parser [SchemaTree]
geniMacros = tillEof $ many geniTreeDef

initType, auxType :: Parser Ptype
initType = do { reserved INITIAL ; return Initial  }
auxType  = do { reserved AUXILIARY ; return Auxiliar }

geniTreeDef :: Parser SchemaTree
geniTreeDef =
  do sourcePos <- getPosition
     family   <- tidentifier
     tname    <- option "" (colon *> tidentifier)
     (pars,iface)   <- geniParams
     theTtype  <- (initType <|> auxType)
     theTree  <- geniTree
     -- sanity checks?
     let treeFail x =
          do setPosition sourcePos -- FIXME does not do what I expect
             fail $ "In tree " ++ T.unpack family ++ ":"
                    ++ T.unpack tname ++ " " ++ show sourcePos ++ ": " ++ x
     let theNodes = T.flatten theTree
         numFeet    = length [ x | x <- theNodes, gtype x == Foot ]
         numAnchors = length [ x | x <- theNodes, ganchor x ]
     when (not $ any ganchor theNodes) $
       treeFail "At least one node in an LTAG tree must be an anchor"
     when (numAnchors > 1) $
       treeFail "There can be no more than 1 anchor node in a tree"
     when (numFeet > 1) $
       treeFail "There can be no more than 1 foot node in a tree"
     when (theTtype == Initial && numFeet > 0) $
       treeFail "Initial trees may not have foot nodes"
     --
     psem     <- option Nothing $ do { keywordSemantics; liftM Just (squares geniSemantics) }
     ptrc     <- option [] $ do { keyword TRACE; squares (many tidentifier) }
     --
     return TT{ params = pars
              , pfamily = family
              , pidname = tname
              , pinterface = sortFlist iface
              , ptype = theTtype
              , tree = theTree
              , ptrace = ptrc
              , psemantics = psem
              }

geniTree :: (Ord v, GeniValLike v) => Parser (T.Tree (GNode v))
geniTree =
  do node <- geniNode
     kids <- option [] (braces $ many geniTree)
             <?> "child nodes"
     -- sanity checks
     let noKidsAllowed t c = when (c node && (not.null $ kids)) $
             fail $ t ++ " nodes may *not* have any children"
     noKidsAllowed "Anchor"       $ ganchor
     noKidsAllowed "Substitution" $ (== Subs) . gtype
     noKidsAllowed "Foot"         $ (== Foot) . gtype
     --
     return (T.Node node kids)

geniNode :: (Ord v, GeniValLike v) => Parser (GNode v)
geniNode = do
    name      <- tidentifier
    nodeType  <- geniNodeAnnotation
    lex_   <- if nodeType == AnnoLexeme
                 then ((tstringLiteral <|> tidentifier) `sepBy` symbol "|") <?> "some lexemes"
                 else return []
    constr <- case nodeType of
                  AnnoDefault -> adjConstraintParser
                  AnnoAnchor  -> adjConstraintParser
                  _           -> return True
    -- features only obligatory for non-lex nodes
    (top,bot) <- if nodeType == AnnoLexeme
                    then option ([],[]) $ try topbotParser
                    else topbotParser
    return $ GN { gnname   = name
                , gtype    = fromAnnotation nodeType
                , gup      = sortFlist top
                , gdown    = sortFlist bot
                , glexeme  = lex_
                , ganchor  = nodeType == AnnoAnchor
                , gaconstr = constr
                , gorigin  = ""
                }
  where
    adjConstraintParser = option False $ reserved ACONSTR >> char ':' >> symbol "noadj" >> return True
    topbotParser = do
        top <- geniFeats <?> "top features"
        symbol "!"
        bot <- geniFeats <?> "bot features"
        return (top,bot)

-- | Should be purely internal type to help parsing.
--   Injection to 'GType'.
--
--   We don't just use GType directly because the annotations convey
--   subtle distinctions that aren't encoded, particularly between
--   lexemes and anchors
data Annotation = AnnoAnchor
                | AnnoLexeme
                | AnnoSubst
                | AnnoFoot
                | AnnoDefault
  deriving Eq

fromAnnotation :: Annotation -> GType
fromAnnotation AnnoLexeme  = Lex
fromAnnotation AnnoAnchor  = Lex
fromAnnotation AnnoSubst   = Subs
fromAnnotation AnnoFoot    = Foot
fromAnnotation AnnoDefault = Other

geniNodeAnnotation :: Parser Annotation
geniNodeAnnotation =
    (keyword TYPE *> ty)                   <|>
    (reserved ANCHOR >> return AnnoAnchor) <|>
    return AnnoDefault
  where
    ty    = choice [ try (symbol s) >> return t | (s,t) <- table ]
    table =
        [ (ANCHOR, AnnoAnchor)
        , (FOOT,   AnnoFoot)
        , (SUBST,  AnnoSubst)
        , (LEX,    AnnoLexeme)
        ]

-- | This makes it possible to read anchored trees, which may be
--   useful for debugging purposes.
--
--   FIXME: note that this is very rudimentary; we do not set id numbers,
--   parse polarities. You'll have to call
--   some of our helper functions if you want that functionality.
geniTagElems :: Parser [TagElem]
geniTagElems = tillEof $ setTidnums `fmap` many geniTagElem

geniTagElem :: Parser TagElem
geniTagElem = do
    family   <- tidentifier
    tname    <- option "" $ (colon *> tidentifier)
    iface    <- (snd `liftM` geniParams) <|> geniFeats
    theType  <- initType <|> auxType
    theTree  <- geniTree
    sem      <- do { keywordSemantics; squares geniSemantics }
    --
    return $ TE { idname      = tname
                , ttreename   = family
                , tinterface  = iface
                , ttype       = theType
                , ttree       = theTree
                , tsemantics  = sem
                , tidnum      = -1 -- provisional id
                , tpolarities = Map.empty
                , tsempols    = []
                , ttrace      = []
                }

-- | 'geniParams' recognises a list of parameters optionally followed by a
--  bang (\verb$!$) and a list of attribute-value pairs.  This whole thing is
--  to wrapped in the parens.
--
--  TODO: deprecate
geniParams :: Parser ([GeniVal], Flist GeniVal)
geniParams = parens $ do
  pars <- many geniValue <?> "some parameters"
  interface <- option [] $ do { symbol "!"; many geniAttVal }
  return (pars, interface)

-- ----------------------------------------------------------------------
-- Morphology
-- ----------------------------------------------------------------------

geniMorphInfo :: Parser [(String,Flist GeniVal)]
geniMorphInfo = tillEof $ many morphEntry

morphEntry :: Parser (String,Flist GeniVal)
morphEntry =
  do pred_ <- identifier
     feats <- geniFeats
     return (pred_, feats)

-- ======================================================================
-- Everything else
-- ======================================================================

-- ----------------------------------------------------------------------
-- Polarities
-- ----------------------------------------------------------------------

-- | 'geniPolarity' associates a numerical value to a polarity symbol,
--  that is, '+' or '-'.
geniPolarity :: Parser Int
geniPolarity = option 0 (plus <|> minus)
  where
    plus  = do { char '+'; return  1   }
    minus = do { char '-'; return (-1) }

-- ----------------------------------------------------------------------
-- keyword
-- ----------------------------------------------------------------------

{-# INLINE keyword #-}
keyword :: String -> Parser String
keyword k =
  do let helper = try $ do { reserved k; colon; return k }
     helper <?> k ++ ":"

{-# INLINE keywordSemantics #-}
keywordSemantics :: Parser String
keywordSemantics = keyword SEMANTICS

-- ----------------------------------------------------------------------
-- language def helpers
-- ----------------------------------------------------------------------

lexer :: TokenParser ()
lexer  = makeTokenParser geniLanguageDef

whiteSpace :: CharParser () ()
whiteSpace = P.whiteSpace lexer

looseIdentifier, identifier, stringLiteral, colon :: CharParser () String
identifier    = P.identifier lexer

tidentifier :: CharParser () Text
tidentifier = T.pack <$> identifier

-- stolen from Parsec code (ident)
-- | Like 'identifier' but allows for reserved words too
looseIdentifier =
 do { i <- ident ; whiteSpace; return i }
 where
  ident =
   do { c <- identStart geniLanguageDef
      ; cs <- many (identLetter geniLanguageDef)
      ; return (c:cs) } <?> "identifier"

stringLiteral = P.stringLiteral lexer
colon         = P.colon lexer

tstringLiteral :: CharParser () Text
tstringLiteral = T.pack <$> stringLiteral


squares, braces, parens :: CharParser () a -> CharParser () a
squares = P.squares lexer
braces  = P.braces  lexer
parens  = P.parens  lexer

reserved, symbol :: String -> CharParser () String
reserved s = P.reserved lexer s >> return s
symbol = P.symbol lexer

-- ----------------------------------------------------------------------
-- parsec helpers
-- ----------------------------------------------------------------------

-- | identifier, permitting reserved words too
identifierR :: CharParser () String
identifierR
  = do { c <- P.identStart geniLanguageDef
       ; cs <- many (P.identLetter geniLanguageDef)
       ; return (c:cs)
       }
       <?> "identifier or reserved word"

tillEof :: Parser a -> Parser a
tillEof p =
  do whiteSpace
     r <- p
     eof
     return r

-- stolen from Parsec and adapted to use UTF-8 input
parseFromFile :: Parser a -> SourceName -> IO (Either ParseError a)
parseFromFile p fname
    = do{ input <- UTF8.readFile fname
        ; return (parse p fname input)
        }
