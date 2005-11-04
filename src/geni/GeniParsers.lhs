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

\chapter{GeniParsers}
\label{cha:GeniParsers}

GeniParsers parses everything that GenI knows how to read natively.  
The parsers are written using the most excellent Parsec library.

\ignore{
\begin{code}
module GeniParsers ( 
  -- test suite stuff
  geniTestSuite, geniSemanticInput,
  -- macros 
  geniMacros,
  -- lexicons
  geniLexicon, geniMorphInfo,
  gdeLexicon,
  -- polarities
  geniPolarities
) where

import GdeParser(gdeLexicon)
-- import TsnlpParser 

import Btypes 
import Data.List (sort)
import qualified Data.Map  as Map 
import qualified Data.Tree as T
import Text.ParserCombinators.Parsec
import Text.ParserCombinators.Parsec.Language (emptyDef)
import Text.ParserCombinators.Parsec.Token (TokenParser, 
    LanguageDef(..), makeTokenParser)
import qualified Text.ParserCombinators.Parsec.Token as P
\end{code}
}

\section{Most parsers}

\ignore{
\begin{code}
\end{code}
}

\section{Test suites}

The test suite format consists of arbitrarily many test cases:

\begin{code}
type SemRes   = ( Sem, [AvPair] ) 
type TestCase = ( String    -- name
                , SemRes    -- semantics / restrictors
                , [String]) -- sentences

geniTestSuite :: Parser [TestCase]
geniTestSuite = 
  do whiteSpace
     s <- many geniTestCase 
     eof
     return s
\end{code}

A test case is composed of an optional test id, some semantic input
\fnref{geniSemanticInput}, followed by any number of sentences.  
Each sentence in the test suite may be optionally preceded by the
keyword 'sentence'.  (We ought to eventually force the use of this
keyword.)

\begin{code}
geniTestCase :: Parser TestCase
geniTestCase =
  do name <- option "" (notSemantics <?> "a test case name")
     (sem,res)   <- geniSemanticInput
     sentences   <- option [] (many sentenceParser)
     return (name, (sem,res), sentences)
  where
    -- parses any identifier BESIDES 'semantics'
    -- ALTERNATELY: we could just make another lexer which
    -- treats 'semantics' as a reserved word, whilst still 
    -- using the regular geni lexer for sentences
    notSemantics :: Parser String
    notSemantics = 
      try $ do { symbol "semantics" ; pzero } <|> identifier
    sentenceParser :: Parser String
    sentenceParser = 
      do optional (keyword "sentence")
         w <- squares (sepBy1 identifier whiteSpace<?> "a sentence") 
         return (unwords w)
\end{code}

\section{Semantics}

\fnlabel{geniSemanticInput} consists of a semantics, and optionally a set of
restrictors.  Restrictors are represented as feature structures.  For more
details about restrictors, see \fnref{detectRestrictors} for details about
restrictors.

\begin{code}
geniSemanticInput :: Parser (Sem,Flist)
geniSemanticInput =
  do keywordSemantics
     sem <- squares geniSemantics 
     res <- option [] $ do { keyword "restrictors" ; geniFeats } 
     --
     return (createHandles $ sortSem sem, res)
  where 
     -- set all anonymous handles to some unique value
     -- this is to simplify checking if a result is
     -- semantically complete
     createHandles :: Sem -> Sem
     createHandles = zipWith setHandle [1..] 
     --
     setHandle i (h, pred, params) =
       let h2 = if h /= GAnon then h 
                else GConst ["genihandle" ++ (show i)]
       in (h2, pred, params) 
\end{code}

\section{Lexicon}

A lexicon is just a whitespace seperated list of lexical entries.
Each lexical entry is 
\begin{enumerate}
\item A lemma
\item The family name of things this lemma anchors to
\item The interface to the tree.  Here's the compicated bit. 
      Either you provide :
\begin{itemize}
\item A list of parameters and an interface, as defined in
      \fnref{geniParams}.   The interface is meant to be unified with
      the tree interface.
\item A feature structure which is to be unifed with the tree interface.
      This is equivalent to the attribute-value pairs above; the only
      difference is that we don't do any parameters, and we use square
      brackets instead of parentheses.
\end{itemize}
\item Optionally: FIXME: add in extension stuff
\end{enumerate}

\begin{code}
geniLexicon :: Parser [ILexEntry]
geniLexicon = 
  do whiteSpace
     l <- sepEndBy1 geniLexicalEntry whiteSpace
     eof
     return l

geniLexicalEntry :: Parser ILexEntry
geniLexicalEntry = 
  do lemma  <- identifier <?> "a lemma"
     family <- identifier <?> "a tree family"
     (params, interface) <- parens paramsParser <|> interfaceParser
     keywordSemantics
     (sem,pols) <- squares geniLexSemantics
     --
     return emptyLE { iword = lemma 
                    , ifamname = family 
                    , iparams = params
                    , ipfeat  = sort interface
                    , isemantics = sem
                    , isempols = pols }
  where 
    paramsParser :: Parser ([GeniVal], Flist)
    paramsParser = do
      params    <- sepEndBy geniValue whiteSpace <?> "some parameters"
      interface <- option [] $ do symbol "!"
                                  sepBy geniAttVal whiteSpace 
      return (params, interface)
    interfaceParser :: Parser ([GeniVal], Flist)
    interfaceParser = do
      interface <- geniFeats
      return ([], interface) <?> "an interface"
\end{code}

\section{Trees}

A macro library is basically a list of trees.

Trees may be defined individually or in anonymous groups.  Definining a
tree as a group does not have any effect other than saving you from
typing ``initial'' or ``auxiliary'' all the time, because if you define a
tree group, you can leave those definitions out.  (Note: you may also
leave them in, but the definition must match the group type)

\begin{code}
geniMacros :: Parser [MTtree]
geniMacros = 
  do whiteSpace
     groups <- many geniTreeGroup 
     eof
     return (concat groups) 

geniTreeGroup :: Parser [MTtree]
geniTreeGroup = 
  do     sepEndBy1 (try $ geniTreeDef $ initType <|> auxType) whiteSpace
     <|> group initType Initial  
     <|> group auxType  Auxiliar
  where 
    group key gtype = 
      do try $ do { symbol "begin"; key }
         t <- sepEndBy (try $ geniTreeDef $ option gtype key) whiteSpace
         symbol "end"  ; key 
         return t
    initType = try $ do { symbol "initial"  ; return Initial  }
    auxType  = try $ do { symbol "auxiliary"; return Auxiliar }
\end{code}

\subsection{Tree definitions}

A tree definition consists of 
\begin{enumerate}
\item a family name, followed by an optional tree id
\item the tree parameters/interface as defined in \fnref{geniParams}
\item (optional) a tree type specification, as parameterised through the
      \fnparam{ttypeP} argument 
\item the tree itself
\end{enumerate}

\begin{code}
geniTreeDef ttypeP =
  do family   <- identifier 
     id       <- option "" $ do { colon; identifier }
     (params,iface)   <- geniParams 
     ttype    <- ttypeP
     theTree  <- geniTree
     --
     return TT{ params = params 
              , pfamily = family
              , pidname = id
              , pfeat = iface 
              , ptype = ttype 
              , tree = theTree
              , ptpolarities = Map.empty 
              , ptpredictors = [] }
\end{code}

\subsection{Tree structure}

A tree is recursively defined as a node followed by an optional list of child
nodes. If there are any child nodes, they appear between curly brackets.

A node consists of 

\begin{enumerate}
\item A node name
\item (optionally) a node type (anchor, lexeme, foot, subst).
\item (if node type is lexeme) a lexeme
\item (optionally) an adjunction constraint 
      (Notes: We only know about null adjunction constraints.
       If the node has a type, it is assumed as having
       a null adjunction constraint)
\end{enumerate}

Example of a tree:
\begin{verbatim}
n2 type:subst [cat:np idx:?Agent]![]
n3[cat:vp idx:?Event]![]
{
  n4 aconstr:noadj [cat:v idx:?Event]![]
  {
    n5 anchor
  }
\end{verbatim}

\begin{code}
geniTree :: Parser (T.Tree GNode)
geniTree = 
  do node <- geniNode
     kids <- option [] (braces $ sepEndBy geniTree whiteSpace) 
             <?> "child nodes"
     return (T.Node node kids)

geniNode :: Parser GNode
geniNode = 
  do name      <- identifier 
     nodeType  <- option "" (do { typeIs; typeParser }
                             <|> try (symbol "anchor"))
     lex    <- if nodeType == lexType 
                  then (sepBy stringLiteral (symbol "|") <?> "some lexemes") 
                  else return [] 
     constr <- if null nodeType 
                  then adjConstraintParser 
                  else return True
     (top_,bot_) <- topbotParser 
     --
     let top   = sort top_
         bot   = sort bot_
         isAnchor  = (nodeType == "anchor")
         nodeType2 = case nodeType of
                       "anchor"  -> Lex
                       "lex"     -> Lex
                       "foot"    -> Foot
                       "subst"   -> Subs 
                       ""        -> Other
                       other     -> error ("unknown node type: " ++ other)
     return $ GN { gnname = name, gtype = nodeType2
                 , gup = top, gdown = bot
                 , glexeme  = lex
                 , ganchor  = isAnchor
                 , gaconstr = constr }
  where 
    lexType    = "lex"
    typeIs     = keyword "type"
    typeParser = choice $ map (try.symbol) $
                   [ "anchor", "foot", "subst", lexType ]
    adjConstraintParser = option False $ do { symbol "aconstr:noadj"; return True }
    topbotParser = option ([],[]) $ try $ 
      do top <- geniFeats <?> "top features" 
         whiteSpace; symbol "!"
         bot <- geniFeats <?> "bot features"
         return (top,bot)
\end{code}

\section{Polarities}

The polarities parser is used for parsing extra polarity input from the
user. For more information, see chapter \ref{cha:Polarity}.

\begin{code}
geniPolarities :: Parser (Map.Map String Int)
geniPolarities =
  do whiteSpace
     p <- many pol 
     eof
     return (Map.fromListWith (+) p)
  where 
    pol = do p <- geniPolarity 
             i <- identifier
             return (i,p)
\end{code}

\section{Morphology}

A morphological information file associates predicates with
morphological feature structures.  Each morphological entry
consists of a predicate followed by a feature structuer.
For more information, see chapter \ref{cha:Morphology}.

\begin{code}
geniMorphInfo :: Parser [(String,Flist)]
geniMorphInfo =
  do whiteSpace
     m <- many morphEntry
     eof
     return m

morphEntry :: Parser (String,Flist)
morphEntry =
  do pred  <- identifier
     feats <- geniFeats
     return (pred, feats)
\end{code}

\section{Generic GenI stuff}

\subsection{Lexer}

Some preliminaries about GenI formats in general - comments start with 
\verb!%!  There is also the option of using \verb'/* */' for embedded
comments.  

\begin{code}
lexer  = makeTokenParser 
         (emptyDef
         { commentLine = "%"
         , commentStart = "/*"
         , commentEnd = "*/"
         , opLetter = oneOf ""
         , reservedOpNames = [""]
         , identLetter = alphaNum <|> oneOf "_'-"
         })

whiteSpace = P.whiteSpace lexer
identifier = P.identifier lexer
stringLiteral = P.stringLiteral lexer
squares   = P.squares lexer
symbol    = P.symbol  lexer
braces    = P.braces  lexer
colon     = P.colon   lexer
parens    = P.parens  lexer
\end{code}

\subsection{Keyword}

A key is nothing simpler than the keyword, followed by a colon.
We factor this into a seperate function to account for whitespace.

\begin{code}
keyword :: String -> Parser String 
keyword k = 
  do let helper = try $ do { symbol k; colon; return k }
     helper <?> k ++ ":"

keywordSemantics = keyword "semantics"
\end{code}

\subsection{Feature structures}

Feature structures take the form  \verb!val : att! with only
whitespace to separate each attval pair.  See \fnref{geniValue} for
details about what the values look like.

\begin{code}
geniFeats :: Parser Flist
geniFeats = option [] $ squares $ sepBy geniAttVal whiteSpace 

geniAttVal :: Parser AvPair
geniAttVal = do
  att <- identifier <?> "an attribute"; colon 
  whiteSpace
  val <- geniValue <?> "a GenI value"
  whiteSpace
  return (att, val)
\end{code}

\fnlabel{geniParams} recognises a list of parameters optionally followed by a
bang (\verb$!$) and a list of attribute-value pairs.  This whole thing is to
wrapped in the parens.

\textbf{Note:} sometimes people prefer not to use parameters - instead they
stick to using the interface.  This is fine, but they should not forget the
bang seperator.

\begin{code}
geniParams :: Parser ([GeniVal], Flist)
geniParams = parens $ do
  params    <- sepEndBy geniValue whiteSpace <?> "some parameters"
  interface <- option [] $ do { symbol "!"; sepBy geniAttVal whiteSpace }
  return (params, interface)
\end{code}

\subsection{Semantics}

A semantics is simply a list of literals. 

A literal can take one of two forms:
\begin{verbatim}
  handle:predicate(arguments)
         predicate(arguments)
\end{verbatim}

The arguments are space-delimited.  Not providing a handle is
equivalent to providing an anonymous one.

\begin{code}
geniSemantics :: Parser Sem
geniSemantics = many (geniLiteral <?> "a literal")

geniLiteral :: Parser Pred
geniLiteral =  
  do handle    <- option GAnon handleParser <?> "a handle"
     predicate <- identifier <?> "a predicate"
     params    <- parens (many geniValue) <?> "some parameters"
     --
     return (handle, predicate, params)
  where handleParser =  
          try $ do { h <- geniValue ; whiteSpace; char ':' ; return h } 
\end{code}

\subsection{Lexical semantics}

A lexical semantics is almost exactly the same as a regular semantics, 
except that each variable may be preceded by a polarity symbol.  When
we figure out how to automate the detection of lexical semantic
polarities, we can start using a regular semantics again.

\begin{code}
geniLexSemantics :: Parser (Sem, [[Int]])
geniLexSemantics = 
  do litpols <- many (geniLexLiteral <?> "a literal")
     let (sem, pols) = unzip litpols
     return (sortSem sem, pols)

geniLexLiteral :: Parser (Pred, [Int])
geniLexLiteral =  
  do (handle, hpol) <- option (GAnon,0) (handleParser <?> "a handle")      
     predicate  <- identifier <?> "a predicate"
     paramsPols <- parens (many geniPolValue) <?> "some parameters"
     --
     let (params, pols) = unzip paramsPols
         literal = (handle, predicate, params)
     return (literal, hpol:pols)
  where handleParser =  
          try $ do { h <- geniPolValue; whiteSpace; colon; return h } 

geniPolValue :: Parser (GeniVal, Int)
geniPolValue = 
  do p <- geniPolarity
     v <- geniValue
     return (v,p)
\end{code}


\subsection{Miscellaneous}

\fnlabel{geniValue} is recognised both in feature structures and in the 
GenI semantics.

\begin{enumerate}
\item As of geni 0.8, variables are prefixed with a question
      mark.
\item The underscore, \verb!_!, and \verb!?_! are treated as anonymous
      variables.
\item Atomic disjunctions are seperated with a pipe, \verb!|!.  Only
      constants may be separated by atomic disjunction
\item Anything else is just a regular only constant
\end{enumerate}

\begin{code}
geniValue :: Parser GeniVal 
geniValue =   (constants  <?> "a constant or atomic disjunction")
          <|> ((try $ anonymous) <?> "_ or ?_")
          <|> (variable   <?> "a variable")
  where 
    question = "?"
    geniId = many1 (alphaNum <|> oneOf "+-") 
    --
    constants :: Parser GeniVal 
    constants = 
      do c <- sepBy1 geniId (symbol "|")
         whiteSpace 
         return (GConst c)
    variable :: Parser GeniVal
    variable = 
      do symbol question 
         v <- identifier 
         return (GVar v)
    anonymous :: Parser GeniVal
    anonymous = 
      do optional $ symbol question 
         symbol "_"
         return GAnon
\end{code}

\subsection{Polarities}

\begin{code}
geniPolarity :: Parser Int
geniPolarity = option 0 (plus <|> minus)
  where 
    plus  = do { char '+'; return  1   }
    minus = do { char '-'; return (-1) } 
\end{code}


