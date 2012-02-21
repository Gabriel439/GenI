{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-
geniserver
Copyright (C) 2011 Eric Kow (on behalf of SRI)

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
-}

module NLP.GenI.Server where

import Control.Exception
import Control.Monad ( liftM, ap )
import Control.Monad.IO.Class ( liftIO )
import Data.Conduit
import Data.Conduit.Lazy
import Data.IORef
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TL
import qualified Data.ByteString.Lazy as B
import Network.Wai
import Network.HTTP.Types (statusOK, status400, Header, Ascii)
import qualified Data.Enumerator.Binary as EB
import qualified Text.JSON as J
import qualified Text.JSON.Pretty as J

import NLP.GenI.Configuration
import NLP.GenI.General (fst3)
import NLP.GenI
import NLP.GenI.Simple.SimpleBuilder

import NLP.GenI.Server.Flags
import NLP.GenI.Server.Instruction

initialise :: Params -> IO ProgState
initialise confArgs = do
  pstRef   <- newIORef (emptyProgState $ setFlagP FromStdinFlg () confArgs)
  _   <- loadGeniMacros pstRef
  _   <- loadLexicon    pstRef
  readIORef pstRef

data GenReq = Dump | Normal

toGenReq :: Request -> Either String GenReq
toGenReq req =
  case pathInfo req of
    ["dump"] -> Right Dump
    []       -> Right Normal
    xs       -> Left $ "Don't know about path: " ++ T.unpack (T.intercalate "/" xs)

parseInstruction :: J.JSON j => B.ByteString -> Either String j
parseInstruction = J.resultToEither . J.decode . TL.unpack . TL.decodeUtf8

application :: ProgState -> Application
application pst req = do
   bss <- liftIO . runResourceT . lazyConsume . requestBody $ req
   let input = (,) `liftM` toGenReq req `ap` parseInstruction (B.fromChunks bss)
   case input of
     Left e    -> return (err e)
     Right tyj -> uncurry heart tyj
  where
   heart ty j = do
      me <- liftIO (handleRequest pst j)
      case me of
         Right p                      -> return (ok ty p)
         Left (BadInputException d e) -> return (err (d ++ " parse error: " ++ show e))

ok :: GenReq -> [GeniResult] -> Response
ok Dump   j = responseLBS statusOK  [contentType "application/json"] $ encodeB $ prettyEncode j
ok Normal j = responseLBS statusOK  [contentType "text/plain"]       $ encodeB $ showResults j

err :: String -> Response
err x = responseLBS status400 [contentType "text/plain"] (encodeB x)

showResults :: [GeniResult] -> String
showResults xs =  unlines . concat $ [ grRealisations g | GSuccess g <- xs ]

handleRequest :: ProgState -> ServerInstruction -> IO (Either BadInputException [GeniResult])
handleRequest pst instr = try $ do
  conf   <- treatArgsWithParams optionsForRequest params (pa pst)
  pstRef <- newIORef (pst { pa = conf })
  loadTargetSemStr pstRef $ "semantics:[" ++ semStr ++ "]"
  -- do the realisation
  let helper builder = fst3 `fmap` runGeni pstRef builder
  results <- case builderType conf of
               SimpleBuilder -> helper simpleBuilder_2p
               SimpleOnePhaseBuilder -> helper simpleBuilder_1p
  return results
 where
  params = gParams    instr
  semStr = gSemantics instr

-- ----------------------------------------------------------------------

encodeB :: String -> B.ByteString
encodeB = TL.encodeUtf8 . TL.pack

contentType :: Ascii -> Header
contentType x = ("Content-Type", x)

prettyEncode :: J.JSON a => a -> String
prettyEncode = J.render . J.pp_value . J.showJSON
