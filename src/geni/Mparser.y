{
module Mparser
 
where 

import ParserLib 

import Btypes (
               Ptype(Initial,Auxiliar,Unspecified),
               Ttree(..), Flist, AvPair,
               GType(Foot, Lex, Subs, Other),
               GNode(..), MTtree, 

               emptyLE, ILexEntry(..), Ptype(..), 

               Sem, Pred, readGeniVal, GeniVal(..))

import qualified Data.Map as Map 

import Data.List (sort)
import qualified Data.Tree 


import System.IO.Unsafe(unsafePerformIO)
}

%name mParser    Input 
%name polParserE PolList
%name lexParser    Lexicon 
%name filParser    FilEntryList 
%name morphParser  MorphInfo  
%name targetSemParser SemR
%name testSuiteParser TestSuite

%tokentype { PosToken }
%monad { E } { thenE } { returnE }

%token 
    anchor   {(Anchor,   _, _)} 
    type     {(Type,     _, _)}
    subst    {(LSubst,   _, _)}
    lexeme   {(Lexeme ,  _, _)}
    foot     {(LFoot,    _, _)}
    aconstr  {(Aconstr,  _, _)}
    noadj    {(Noadj,    _, _)}
    str      {(Str $$,   _, _)} 
    initial  {(Init,     _, _)} 
    auxiliar {(Aux,      _, _)} 
    family   {(FamilyTok,_, _)}
    begin    {(Begin,    _, _)}
    end      {(End,      _, _)}
    id       {(ID $$,    _, _)} 
    num      {(Num $$,    _, _)} 
    '['      {(OB,       _, _)} 
    ']'      {(CB,       _, _)} 
    '{'      {(OC,       _, _)} 
    '}'      {(CC,       _, _)} 
    '('      {(OP,       _, _)} 
    ')'      {(CP,       _, _)} 
    '!'      {(Bang,     _, _)} 
    '+'      {(PlusTok,  _, _)}
    '-'      {(MinusTok, _, _)}
    '='      {(EqTok, _,_)}
    ','      {(Comma,    _, _)} 
    ':'      {(Colon,    _, _)} 
    '|'      {(BarTok,   _, _)}
    sem   {(Semantics,    _, _)}
    res   {(RestrictorsTok, _,_)}

%%

{- -----------------------------------------------------------------
   morphological information 
   ----------------------------------------------------------------- -}

MorphInfo :: { [(String,[AvPair])] } 
MorphInfo :                 { [] }
          | Morph MorphInfo { $1:$2 }

Morph :: { (String,[AvPair]) } 
Morph : id '[' FeatList ']' { ($1,$3) }

{- -----------------------------------------------------------------
   lexicon 
   ----------------------------------------------------------------- -}

Lexicon :: { [ILexEntry] }
Lexicon : LInput  {$1}

LInput :: { [ILexEntry] }
LInput : {-empty-}        {[]}
       | LexEntry LInput {$1:$2}

LexEntry :: { ILexEntry }
LexEntry: id id '(' IDFeat ')' LexSem
        {emptyLE { iword   = $1,
                   ifamname = $2,
                   iparams = fst $4,
                   ipfeat  = sort $ snd $4,
                   isemantics = fst $6,
                   isempols = snd $6
                 }
        }
 | id id '[' FeatList ']' LexSem
         {emptyLE { iword   = $1,
                    ifamname = $2,
                    ipfeat  = sort $ $4,
                    isemantics = fst $6,
                    isempols = snd $6
                  }
         }

{- lexical semantics (not the same as input semantics) 
   but if we ever figure out how to autodetect the 
   sem polarities, then we should try to merge them back 
-}

LexSem :: { (Btypes.Sem,[LpSemPols]) }
LexSem: {-empty-}                {([],[])}
   | sem ':' '[' LexListPred ']' 
      {(createHandleVars $4, extractSemPolarities $4)}

LexListPred :: { [LpRawPred] }
LexListPred : {-empty-}           {[]}
            | LexPred LexListPred {$1:$2}

LexPred :: { LpRawPred }
LexPred : PolId ':' id '(' LexParams ')'  {( (    $1, $3), $5)}
        |           id '(' LexParams ')'  {( ((GAnon,0), $1), $3)}

LexParams :: { [LpParam] }
LexParams : {-empty-} {[]}
          | PolId LexParams {$1:$2}

PolId :: { LpParam }
PolId : '+' id  { (readGeniVal $2, 1) }
      | '-' id  { (readGeniVal $2,-1) }
      |     id  { (readGeniVal $1, 0) }


{- -----------------------------------------------------------------
   .fil lexicon format 
   see the common grammar manifesto
   ----------------------------------------------------------------- -}

FilEntryList :: { [ILexEntry] }
FilEntryList : {-empty-}              {[]}
             | FilEntry FilEntryList  {$1:$2}

FilEntry :: { ILexEntry }
FilEntry : id '[' FilTerList ']' '(' FilFeatList ')'
         { emptyLE { iword   = $1,
                     iparams = [],
                     ipfeat  =  $6,
                     ifilters = $3
                   }
         }

FilTerList :: { {-FilTerList-} [AvPair] }
FilTerList : {-empty-}               {[]}
           | FilTer                  {[$1]}
           | FilTer ',' FilTerList   {($1:$3)}

FilTer :: { AvPair }
FilTer : id     ':' FeatVal {($1,$3)}
       | family ':' FeatVal {("family",$3)} {- don't interpret family as a keyword here -}

FilFeatList :: { {-FilFeatList-} [AvPair] }
FilFeatList : {-empty-}               {[]}
            | FilFeat                 {[$1]}
            | FilFeat ',' FilFeatList {($1:$3)}

{- note that we treat equations like foo.bar.baz as a single string -}
FilFeat :: { AvPair }
FilFeat : id '=' FeatVal {($1,$3)}

{- -----------------------------------------------------------------
   macros 
   ----------------------------------------------------------------- -}

{- lists of trees -}

Input :: { [MTtree] }
Input : 
      { [] }
 | DefU Input
     {%
       let tn = pidname $1 
       in failE ("tree " ++ tn ++ " is of unspecified type") }
 | DefI Input
     { $1 : $2 }
 | DefA Input
     { $1 : $2 }
 | begin initial DefIUs end initial Input
     { (map (\e -> e {ptype = Initial}) $3) ++ $6 }
 | begin auxiliar DefAUs end auxiliar Input 
     { (map (\e -> e {ptype = Auxiliar}) $3) ++ $6 }

DefAUs :: { [MTtree] }
DefAUs : 
      { [] }
 | DefI DefAUs
      {% 
        let tn = pidname $1
        in failE ("tree " ++ tn ++ " is marked initial " 
                  ++ "within a block of auxiliary trees")
      }
 | DefA DefAUs 
      { $1 : $2 } 
 | DefU DefAUs 
      { $1 : $2 } 
 
DefIUs :: { [MTtree] }
DefIUs : 
      { [] }
 | DefA DefIUs
      {% 
        let tn = pidname $1
        in failE ("tree " ++ tn ++ " is marked auxiliary " 
                  ++ "within a block of initial trees")
      }
 | DefI DefIUs 
      { $1 : $2 } 
 | DefU DefIUs 
      { $1 : $2 } 

{- ----- trees ----- -}

{- definitions -}
 
DefU :: { MTtree }
DefU :
   TreeFamName '(' IDFeat ')' TopTree
     { buildTree Unspecified $1 $3 emptyPolPred $5 }  
 | TreeFamName '(' IDFeat ')' '(' PolPred ')' TopTree
     { buildTree Unspecified $1 $3 $6           $8 }

DefI :: { MTtree }
DefI :
   TreeFamName '(' IDFeat ')' initial TopTree
     { buildTree Initial $1 $3 emptyPolPred $6 }
 | TreeFamName '(' IDFeat ')' '(' PolPred ')' initial TopTree
     { buildTree Initial $1 $3 $6           $9 }

DefA :: { MTtree }
DefA :
   TreeFamName '(' IDFeat ')' auxiliar TopTree
     { buildTree Auxiliar $1 $3 emptyPolPred $6 }
 | TreeFamName '(' IDFeat ')' '(' PolPred ')' auxiliar TopTree
     { buildTree Auxiliar $1 $3 $6           $9 }

{- tree family / name -}

TreeFamName :: { (String,String) }
TreeFamName : id         {($1,"")}
            | id ':' id  {($1,$3)}
            | num        {(show $1,"")}
            | num ':' id {(show $1,$3)}

{- polarities and predictors -}

PolPred :: { (MpPolarities, MpPredictors) }
PolPred : PolList                   { ($1,[]) }
        | PolList '!' PredictorList { ($1,$3) }

PolList :: { MpPolarities }
PolList :                   {Map.empty}
        | Charge id PolList {Map.insertWith (+) $2 $1 $3}

PredictorList :: { MpPredictors }
PredictorList : 
      {[]}
  | PolVal Predictor PredictorList 
      {($2,$1):$3}
  | PolVal num Predictor PredictorList 
      {(map (const ($3,$1)) [1..$2]) ++ $4}

{- FIXME: not sure about GAnon: should check if ever use predictors again -}
Predictor :: { AvPair }
Predictor: id        { ($1,GAnon) } 
         | id ':' id { ($1,readGeniVal $3) }

Charge :: { Int }
Charge: PolVal {($1)}
      | PolVal num {($1 * $2)}

PolVal :: { Int }
PolVal: '+' {(1)}
      | '-' {(-1)}

{- the trees themselves -}

TopTree :: { TrTree GNode }
TopTree : id Descrip '{' ListTree '}'
     { buildTreeNode $1 $2 $4 } 

ListTree :: { [TrTree GNode] }
ListTree :                     {[]}
         | id Descrip ListTree {(buildTreeNode $1 $2 []) : $3 }
         | TopTree ListTree    {($1:$2)}

Descrip :: { MpStuff }
Descrip :
   anchor
     {("anchor","",nullpair)}
 | type ':' anchor  TopBotF
     {("anchor","",$4)} 
 | type ':' lexeme str TopBotF
     {("lexeme",$4,$5)}
 | type ':' lexeme str 
     {("lexeme",$4,nullpair)}
 | type ':' subst TopBotF 
     {("subst","",$4)}
 | type ':' foot TopBotF 
     {("foot","",$4)} 
 | aconstr ':' noadj TopBotF 
     {("aconstr","",$4)} 
 | TopBotF 
     {("","",$1)} 

TopBotF :: { (Flist,Flist) }
TopBotF : '[' FeatList ']' '!' '[' FeatList ']'
    {($2,$6)}

{- -----------------------------------------------------------------
   test suite and input semantics 
   ----------------------------------------------------------------- -}

TestSuite :: { [TpCase] }
TestSuite: TestCase           { [$1] } 
         | TestCase TestSuite { $1 : $2 } 

TestCase :: { TpCase }
TestCase:    SemR Sentences { ("",$1,$2) }
        | id SemR Sentences { ($1,$2,$3) }

SemR :: { (TpSem, [AvPair]) }
SemR: Sem     { ($1,[]) }
    | Sem Res { ($1,$2) }

{- sentences -}

Sentences :: { [String] }
Sentences:                    { [] }
         | Sentence Sentences { $1 : $2 }

Sentence :: { String }
Sentence: '[' String ']' { $2 }

String :: { String }
String: id { $1 }
      | id String { $1 ++ " " ++ $2 }

{- restrictors -}

Res :: { [AvPair] }
Res : res ':' '[' FeatList ']' { $4 }

 
{- -----------------------------------------------------------------
   generic stuff 
   ----------------------------------------------------------------- -}

IDList :: { [GeniVal] }
IDList : {-empty-}  {[]} 
       | id IDList  {(readGeniVal $1):$2} 

IDFeat :: { ([GeniVal],[AvPair])}
IDFeat : IDList               { ($1,[]) }
       | IDList '!' FeatList  { ($1,$3) }

Num :: { Int }
Num: num     { $1 }
   | '-' num { (-$2) }

{- feature structures -}

FeatList :: { {-FeatList-} [AvPair] }
FeatList : {-empty-}               {[]} 
         | id  ':' FeatVal FeatList {($1,$3):$4}
           {- let's not be shocked by "lex" -}
         | lexeme ':' FeatVal FeatList {("lex",$3):$4} 

FeatVal :: { GeniVal } 
FeatVal: id  {readGeniVal $1}
       | num {GConst [show $1]}
       | '+' {GConst ["+"]}
       | '-' {GConst ["-"]}
       | ConstList { GConst (map rejectNonGConst $1) }

ConstList :: { [String] }
ConstList : id '|' id { [$1,$3] } 
          | id '|' ConstList { $1 : $3 } 

{- semantics -}

Sem :: { Btypes.Sem }
Sem: sem ':' '[' ListPred ']' {$4}

ListPred :: { [Btypes.Pred] }
ListPred : {-empty-}         {[]}
         | Pred ListPred     {$1:$2}

Pred :: { Btypes.Pred }
Pred : id '(' Params ')'  {(GAnon, $1, $3)}
     | id ':' id '(' Params ')' {
        unsafePerformIO $ do  
          putStrLn "Warning: handle detected and ignored (we don't do handles)"
          return (GAnon,$3,$5)
      }

Params :: { [GeniVal] }
Params : {-empty-} {[]}
       | id Params {(readGeniVal $1):$2}

{- tree representation for semantics: 
   for now, i don't want to deal with this, or handles
-- Sem :: { TpSem }
-- Sem : sem ':' '[' ListPred ']' { $4 }
-- 
-- ListPred :: { TpSem } 
-- ListPred :               {[]}
--          | Pred ListPred {$1:$2}
-- 
-- Pred :: { Tree TpPred }
-- Pred : id ':' id '(' Params ')'  {(Node ($1,$3) $5)}
--      | id '(' Params ')'         {(Node ("",$1) $3)}
-- 
-- Params :: { TpSem } 
-- Params :             {[]}
--        | id Params   {(Node ("",$1) []):$2}
--        | Pred Params {$1:$2}
-}


{

polParser x = case polParserE x of 
                Ok p     -> p
                Failed e -> error e

-- -------------------------------------------------------------------
-- dealing with errors 
-- -------------------------------------------------------------------


happyError :: [PosToken] -> E a
happyError = parserError
}


 

