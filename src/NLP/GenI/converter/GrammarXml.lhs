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

\chapter{XML Parser}
\label{cha:xml}

A simple DOM-like parser (using HaXml) for grammars in XML format.
This produces a set of trees indexed by their name.

\begin{code}
module GrammarXml where
\end{code}

\ignore{
\begin{code}
import Data.Char
import qualified Data.Map as Map
import Data.List (partition,sort)
import Data.Tree
import MonadState (State, 
                   runState,
                   get, 
                   put)
import Text.XML.HaXml.Types
import Text.XML.HaXml.Combinators
import Text.XML.HaXml.Parse

import Btypes
  ( AvPair, Flist, ILexEntry(..)
  , GType(Subs,Foot,Lex,Other)
  , GNode(..), Macros, Ttree(..)
  , GeniVal(GConst, GVar)
  , emptyGNode, emptyMacro, Ptype(..), Pred, Sem)
-- import Tags(emptyTE,TagElem(..),Tags,TagSite,addToTags)
\end{code}
}

%% ======================================================================
%\section{Lexicon}
%% ======================================================================
%
%A lexicon associates some lemma with a tree family.
%FIXME: For the moment, we do not handle coanchors!  We actually
%drop a good deal of the information that is the lexicon.
%
%\begin{code}
%parseXmlLexicon :: String -> [ILexEntry]
%parseXmlLexicon g = 
%  -- extract a CElem out of the String
%  let (Document _ _ ele) = xmlParse "" g 
%      c = CElem ele
%      -- processing phase
%      lexF = tag "tagml" /> tag "lexicalizationLib" 
%             /> tag "lexicalization"
%      lex  = lexF c
%  in map parseLex lex
%\end{code}
%
%Lexical entries can be really fancy.  Each lexical entry looks 
%a little like this:
%
%\begin{verbatim}
%<lexicalization>
%      <tree>
%        <fs>
%          <f name="family">
%            <sym value="commonnoun"/></f></fs></tree>
%      <anchor noderef="anchor">
%        <lemmaref name="agneau" cat="n"/></anchor></lexicalization>
%\end{verbatim}
%
%From the above piece of XML, we would extract the following
%information: family = commonnoun, anchor = agneau
%
%\begin{code}
%parseLex :: Content -> ILexEntry
%parseLex l = 
%  let -- getting the family name 
%      lFeatsF = keep /> tag "tree" /> featStructF /> featF
%      feats   = map parseFeature (lFeatsF l)
%      famFeats = filter (\ (a,_) -> a == "family") feats
%      fam = if null famFeats 
%            then "UNKWNOWN" 
%            else (snd.head) famFeats
%      -- getting the lemma 
%      lemmarefF = keep /> tag "anchor" /> tag "lemmaref"
%      catF   = attributed "cat" lemmarefF
%      cat    = concatMap fst (catF l) -- should only be one element 
%      lemmaF = attributed "name" lemmarefF
%      lemma  = concatMap fst (lemmaF l) -- should only be one element 
%      -- creating a lexical entry: note that we leave the
%      -- semantics empty; this will have to be read from 
%      -- another file
%  in ILE{ iword = lemma
%        , icategory = cat
%        , ifamname = fam
%        , iparams = []
%        , ipfeat = []
%        , ifilters = []
%        , iptype = Unspecified
%        , isemantics = []
%        , isempols = []
%        , icontrol = ""
%  }
%\end{code}


% ======================================================================
\section{Macros}
% ======================================================================

\begin{code}
type MTree = Ttree GNode
\end{code}

Macros can either be organised as a simple list of macros, or be grouped into
subgrammars.  The list of macros organisation is with traditional, basic
lexical selection where each macro identifies what family it belongs to. The
subgrammar organisation is useful if you have a third party anchoring mechanism
that just spits out the trees relevant to your lexical selection 
(see section \ref{sec:cgm_selection}).  Both organisations of macros are handled
in essentially the same manner : we return a list of trees.

\paragraph{parseXmlGrammar} handles the basic list of macros.  

\begin{code}
parseXmlGrammar :: String -> Macros
parseXmlGrammar g = 
  -- extract a CElem out of the String
  let (Document _ _ ele []) = xmlParse "" g 
      c = CElem ele
      -- processing phase
      entriesF = tag "grammar" /> tag "entry"
      entries  = entriesF c
  in map parseEntry entries 
\end{code}

\paragraph{parseEntryAndSem and parseEntry} do the job of parsing
a single TAG tree. 

\begin{code}
parseEntryAndSem :: Content -> (MTree,Sem) 
parseEntryAndSem e =
  let litF = keep /> tag "semantics" /> tag "literal"
      sem  = map parseLiteral (litF e)
  in  (parseEntry e, sem)

parseEntry :: Content -> MTree
parseEntry e =
  let synF = keep /> tag "tree"    
      trcF = keep /> tag "trace"    
      intF = keep /> tag "interface"
      -- litF = keep /> tag "semantics" /> tag "literal"
      -- sem  = map parseLiteral (litF e)
      syn  = synF e
      trc  = trcF e
      int  = intF e
      -- read the tree name 
      nameF = attributed "name" keep
      name  = concatMap fst (nameF e) -- should only be one element 
      -- read the tree family name 
      famNameF = keep /> tag "family" /> txt 
      famName  = unwrap (famNameF e) -- should only be one element 
      -- build the tree 
      t = t2 { pfamily = famName
             , pidname = name
             , params  = fst pf 
             , pfeat   = snd pf }
          where t2 = if null syn 
                     then emptyMacro 
                     else parseTree (head syn)
                pf = if null int 
                     then ([],[])
                     else parseInterface (head int)
  in t
\end{code}

% ----------------------------------------------------------------------
\subsection{Syntax}
% ----------------------------------------------------------------------

Below, we're going need to use a state monad to keep track of some stuff like
node numbering, the tree type, etc.  Here will be the contents of the
state.

\begin{code}
data TreeInfo = TI {
  -- tiAdjnodes :: [TagSite],
  -- tiSubstnodes :: [TagSite],
  tiNum     :: Int,
  -- tiLex     :: String,
  tiHasFoot :: Bool
} 
\end{code}

Tree parsing consists of building up the tree with the recursive
function parseNode, and then extracting (from the State monad)
some information which is global to the tree.

\begin{code}
parseTree :: Content -> MTree 
parseTree t = 
  let nodeF  = keep /> tag "node"
      node   = nodeF t
      initTi = TI { tiNum = 0, tiHasFoot = False }
                    -- tiAdjnodes = [], tiSubstnodes = [] }
      (parsedTr,finalTi)  = runState (parseNode $ head node) initTi
      (tr,info) = if null node  
                  then (Node emptyGNode [], initTi) 
                  else (parsedTr, finalTi)
  in emptyMacro { tree = tr
                , ptype = if (tiHasFoot info) then Auxiliar else Initial
                }
\end{code}

We recurse through a basic tree structure to build the TAG tree.  Nodes 
have children which are also nodes.  The structure is something like this:

\begin{verbatim}
<node type="none">
  <narg>
  <fs>
    <f name="cat">
      ...
    </f>
    <feature name="top"><avm>
        ...
    </avm></feature>
  <fs>
  </narg>
  <node mark="subst">  <-- RECURSION HERE
       ...
  </node>
</node>
\end{verbatim}

The annoying thing is the features.  The MG builds recursive feature
structures, where the top and bottom features are substructures of 
the global fs.  GenI, on the other hand, assumes two flat feature 
lists, top and bottom.   We work around this by simply assuming that
the fs recursion never goes further than that one level, and that 
global features belong to both the top and bottom lists.

\begin{code}
parseNode :: Content -> State TreeInfo (Tree GNode)
parseNode n = do
  st <- get
  let -- the fs parent structure 
      wholeF = keep /> tag "narg" /> featStructF /> featF
      -- detecting top, bottom and global features
      makeAttrF v = attrval ("name", AttValue [Left v])
      topAttrF = makeAttrF "top"
      botAttrF = makeAttrF "bot"
      topF = subFeatF topAttrF
      botF = subFeatF botAttrF 
      subFeatF av = (av `o` wholeF) /> featStructF /> featF
      -- global features are neither top nor bottom
      gloF = (wholeF `without` topAttrF) `without`  botAttrF
      -- saving the feature lists 
      topFl  = map parseFeature (topF n)
      botFl  = map parseFeature (botF n)
      gloFl' = map parseFeature (gloF n)
      -- reading the node type
      ntypeF    = attributed "type" keep
      ntypeStr  = concatMap fst (ntypeF n) -- should only be one element 
      ntype'    = case ntypeStr of 
                    "subst"  -> Subs
                    "foot"   -> Foot
                    "anchor" -> Lex
                    _        -> Other
      -- hard setting the lexeme 
      isLexeme (a,_) = a == "phon" || a == "lex"
      (lexL, gloFl)  = partition isLexeme gloFl'
      (ntype, lex)   = if null lexL 
                       then (ntype', "") 
                       -- FIXME: hack: we sort lexL so that priority 
                       -- is given to the lex attribute (lexicographically)
                       else (Lex   , snd $ head $ sort lexL) 
      aconstr  = (ntype == Subs || ntype == Foot || ntypeStr == "nadj")
      -- the node name is just the counter
      name = show $ tiNum st
      -- saving the results in a Gnode
      gn = GN { gnname  = name,
                gup     = sort $ topFl ++ gloFl,
                gdown   = sort $ botFl ++ gloFl,
                ganchor = (null lex && ntype == Lex),
                glexeme = lex,
                gtype   = ntype,
                gaconstr = aconstr }
  -- update the monadic state
  let st2 = st { tiNum = (tiNum st) + 1,
                 -- tiLex = if ntype == Lex then lex else (tiLex st),
                 tiHasFoot = (tiHasFoot st) || (ntype == Foot) }
  put st2
  -- recursion to the kids  
  let kidsF  = keep /> tag "node"
  kids <- mapM parseNode (kidsF n)
  -- output the node
  return (Node gn kids)
\end{code}

% ----------------------------------------------------------------------
\subsection{Semantics}
% ----------------------------------------------------------------------

We parse each literal in the tree semantics separately.  Note the
case-conversion for labels.  This is because labels are assumed to
be constants.  We discriminate between arguments of the form
\verb$<const>Foo</const>$ or \verb$<var>Bar</var>$ in the same way as
parseFeatVal above.

\begin{code}
parseLiteral :: Content -> Pred 
parseLiteral lit =
  let labelF    = children `o` (keep /> tag "label")
      predF     = children `o` (keep /> tag "predicate")
      label     = (concatParseSym . labelF) lit
      predicate = (concatParseSym . predF) lit
      concatParseSym = concatMap parseSym -- assumes a singleton list
      -- arguments
      argsF     = children `o` (keep /> tag "arg") 
      arguments = map parseSym (argsF lit)
  in (label, predicate, arguments)
\end{code}

% ----------------------------------------------------------------------
\subsection{Interface}
% ----------------------------------------------------------------------

The interface is the mechanism which allows us to parameterise the tree
and to set its semantic indices.  We treat the interface as a feature
structure which is associated with the entire tree.  For example, a tree
like \verb$S(N [idx:X], V, N [idx:Y])$ could have an interface
\verb$[arg0:X, arg1:Y]$.  In order to instantiate the tree with the
semantics \texttt{hates(h,m,j)}, we could set \verb$arg0$ to \texttt{m}
and \verb$arg1$ to j.

In the TAGMLish format, the following FS would be produced by the XML
below.
\fs{\it anch:manger\\ 
    \it arg0:?A\\
    \it arg1:?I\\
    \it obj:?I\\  
    \it suj:?A\\}

\begin{verbatim}
<interface>
  <fs>
    <f name="anch"><sym value="manger"/></f>
    <f name="arg0"><sym varname="@A"/></f>
    <f name="arg1"><sym varname="@I"/></f>
    <f name="obj"> <sym varname="@I"/></f>
    <f name="suj"> <sym varname="@A"/></f>
  </fs>
</interface>
\end{verbatim}

\begin{code}
parseInterface :: Content -> ([String], Flist)
parseInterface int =
  let iFeatsF  = keep /> featStructF /> featF
      feats    = map parseFeature (iFeatsF int)
  in ([], feats)
\end{code}

% ----------------------------------------------------------------------
\section{XML Content to Haskell}
% ----------------------------------------------------------------------

Turns a Content into a String.  Returns empty string if the Content is
not a CString

\begin{code}
unwrap :: [Content] -> String
unwrap [(CString _ c)] = c          
unwrap _ = ""
\end{code}

% ----------------------------------------------------------------------
\section{Miscellaneous}
% ----------------------------------------------------------------------

\paragraph{XML snippets}

We collect bits and pieces of the XML format as global functions for
use throughout the code.

\begin{code}
featStructF = tag "fs"
featF       = tag "f"
\end{code}

\paragraph{parseFeature} Extracts a an attribute-value pair (att,value) out of
the XML.

\begin{verbatim}
<f name="att">
  <sym varname="value"/>
</f>
\end{verbatim}

Disjunctions look like this in the XML:

\begin{verbatim}
<vAlt coref="@X">
 <sym value="foo"/>
 <sym value="bar"/>
</vAlt>
\end{verbatim}
\begin{code}
parseFeature :: Content -> AvPair
parseFeature f =
  let -- parsing the attribute
      -- the TAG fs attribute is expressed as the value of XML attribute "name"
      subfeatF = attributed "name" keep
      feat     = concatMap fst (subfeatF f) -- should only be one element 
      -- parsing the value
      symF  = keep /> tag "sym"
      disjF = attributed "coref" (keep /> tag "vAlt")
      -- converting the value to GenI format
      readAttr fn = concatMap fst (fn f)
      -- FIXME: need to handle disjunction properly
      disjStr     = (drop 1 . readAttr) disjF
      -- deciding what type of feature we have
      val = if null disjStr 
            then concatMap parseSym (symF f) -- singleton list 
            else disjStr
  in (feat, val)
\end{code}

\paragraph{parseSym} converts sym tags into GenI constants or variables.

\begin{enumerate}
\item constants are of the form \verb$<sym value="foo"/>$.  
\item variables are of the form \verb$<sym varname="@Bar"/>$.
\end{enumerate}

\begin{code}
parseSym :: Content -> GeniVal 
parseSym s =
  let -- parsing the value
      varF     = varAttrF keep 
      varAttrF = attributed "varname"
      constF   = attributed "value" keep 
      -- converting the value to GenI format
      readAttr fn = concatMap fst (fn s)
      varStr   = (drop 1 . readAttr) varF 
      constStr = readAttr constF
  in  -- deciding what type of feature we have
      if null varStr then GConst [constStr] else GVar varStr
\end{code}
