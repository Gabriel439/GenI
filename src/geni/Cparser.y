{
module Cparser
 
where 

import Btypes (ILexEntry)
import ParserLib(Token(..),PosToken,simpleParserError)
import Data.List (intersperse)

}

%name cParser Input
%name giParser GramInput
%tokentype { PosToken }

%token 
    macros      {(MacrosTok,      _, _)} 
    lexicon     {(LexiconTok,     _, _)}  
    semlex      {(SemLexiconTok,  _, _)}
    morphinfo   {(MorphInfoTok,   _, _)}
    rootcats    {(RootCategoriesTok, _,_)}
    grammar     {(GrammarTok,      _, _)} 
    grammartype {(GrammarType,     _, _)}
    cgmanifesto {(CGManifestoTok,  _, _)}
    morphcmd    {(MorphCmdTok,     _, _)}
    tsem        {(TSemanticsTok,  _, _)}
    tsuite      {(TestSuiteTok,  _, _)}
    tcases      {(TestCasesTok,  _, _)}
    graphical   {(GraphicalTok,   _, _)}
    optimisations {(Optimisations, _,_)}
    polarised    {(Polarised,   _, _)}
    polopts      {(PolOptsTok,  _, _)}
    adjopts      {(AdjOptsTok,  _, _)}
    autopol      {(AutoPol,     _,_)}
    polsig       {(PolSig,      _,_)}
    predicting   {(Predicting,  _, _)}
    semfiltered  {(SemFiltered,  _, _)}
    chartsharing {(ChartSharing,  _, _)}
    orderedadj   {(OrderedAdj,  _, _)}
    footconstr   {(FootConstraint, _, _)}
    batch        {(Batch,  _, _)}
    repeat       {(Repeat,  _, _)}
    extrapol     {(ExtraPolarities,  _, _)}
    id           {(ID $$,       _, _)}
    true       {(TTT,         _, _)}
    false      {(FFF,         _, _)}
    '='        {(EqTok,       _, _)} 
    num        {(Num $$,    _, _)} 
    '!'        {(Bang, _, _)}
    '+'        {(PlusTok, _, _)}
    '-'        {(MinusTok, _, _)}
    ','        {(Comma, _, _)}
 %%

{- -----------------------------------------------------------------
   configuration file 
   ----------------------------------------------------------------- -}

Input :: { [[CpPair]] }
Input : InputList
     {if (null $1) then [] else [$1]}
 | InputList '!' Input
     {($1:$3)}

InputList :: { [CpPair] }
InputList :
     {[]}
 | repeat '=' num InputList
     {(Repeat,show $3):$4}
 | idkey '=' id InputList
     {(untok $1,$3):$4}
 | grammartype '=' gtype InputList 
     {(untok $1,show $3):$4}
 | boolkey '=' true InputList
     {($1,"True"):$4}
 | boolkey '=' false InputList
     {($1,"False"):$4}
 | tcases  '=' idList InputList
     {(untok $1,unwords $3):$4}
 | optimisations '=' OptList InputList
     {(untok $1, $3):$4}
 | extrapol '=' PolList InputList
     {(untok $1, $3):$4}

idkey :: { PosToken }
idkey:   grammar  {$1}  
       | tsem     {$1}  
       | tsuite   {$1}
       | morphcmd {$1}

boolkey :: { Token }
boolkey: graphical  {GraphicalTok}

idList :: { [String] }
idList :            { [] }
       |  id idList {$1:$2}

{- optimisations -}

OptList :: { String }
OptList : OptListI { unwords $1 }

OptListI :: { [String] }
OptListI :                     { [] }
         | optkey              { [(show $1)] }
         | optkey ',' OptListI {  (show $1) : $3 }

optkey :: { Token }
optkey: polopts      {PolOptsTok}
      | adjopts      {AdjOptsTok}
      | polarised    {Polarised}
      | autopol      {AutoPol}
      | polsig       {PolSig}
      | predicting   {Predicting}
      | semfiltered  {SemFiltered}
      | chartsharing {ChartSharing}
      | orderedadj   {OrderedAdj}
      | footconstr   {FootConstraint}
      | batch        {Batch}

{- extra polarities -} 

PolList :: { String } 
PolList :                   {""}
        | Charge id PolList {$1 ++ $2 ++ $3}

Charge :: { String }
Charge: PolVal {$1}
      | PolVal num {$1 ++ (show $2)}

PolVal :: { String }
PolVal: '+' {"+"}
      | '-' {"-"}

{- -----------------------------------------------------------------
   grammar index file 
   ----------------------------------------------------------------- -}

GramInput :: { [CpPair] }
GramInput : GramInputList {$1}

GramInputList :: { [CpPair] }
GramInputList : 
     {[]}
 | gramIdkey '=' id GramInputList
     {(untok $1,$3):$4}
 | rootcats  '=' idlist GramInputList
     {(untok $1,unwords $3):$4}

idlist :: { [String] }
idlist : id            { [$1]  }
       | id ',' idlist { $1:$3 }

gramIdkey :: { PosToken }
gramIdkey: lexicon   {$1}  
         | macros    {$1}  
         | semlex    {$1}
         | morphinfo {$1}

gtype :: { Token }
      :  cgmanifesto { untok $1 }

{

type CpPair = (Token,String)

untok (a,_,_) = a

happyError = simpleParserError
}

