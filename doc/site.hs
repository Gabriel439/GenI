{-# LANGUAGE OverloadedStrings #-}
import Control.Arrow ((>>>))
import System.FilePath

import Hakyll

main :: IO ()
main = hakyll $ do
    match "manual/images/*" $ do
        route   idRoute
        compile copyFileCompiler

    match "css/*" $ do
        route   idRoute
        compile compressCssCompiler

    match "templates/*" $ compile templateCompiler

    match "homepage/*.md" $ do
        route   $ homepageRoute `composeRoutes` setExtension "html"
        compile defaultPageCompiler

    match "homepage/*" $ do
        route   $ customRoute (takeFileName . toFilePath)
        compile copyFileCompiler

    match "manual/*.md" $ do
        route   $ setExtension "html"
        compile defaultPageCompiler

homepageRoute = customRoute (takeFileName . toFilePath)

defaultPageCompiler =
        pageCompiler
            >>> applyTemplateCompiler "templates/default.html"
            >>> relativizeUrlsCompiler
