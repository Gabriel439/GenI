module Main where

import MinimalGenI
import Data.List ( intercalate )
import System.Environment ( getArgs )

main = do
  args <- getArgs
  (mac, lex, lex2, sem ,rf, morphcmd) <- case args of
                  [x1,x2,x3,x4,x5,x6] -> return (x1, x2, x3, x4, x5, x6)
                  _ -> fail "Usage: test macro-file lex-file lex-file-2 sem-file root-feature morphcmd"
  lexStr2 <- readFile lex2
  testSem <- readFile sem
  pst <- either (fail . showGenIException) return =<< geniInit mac lex morphcmd
  xs  <- sequence [ geniRealize pst ""      testSem rf
                  , geniRealize pst lexStr2 testSem rf
                  , geniRealize pst ""      testSem rf
                  ]
  putStrLn $ "[" ++ intercalate "," xs ++ "]"

-- evidence that it was caught in the wrapper
showGenIException e = "Wrapper caught an exception from GenI:\n" ++ show e
