{-# LANGUAGE OverloadedStrings   #-}

module Main where

import qualified Network.WebSockets as WS
import qualified Data.Aeson           as A
import Data.Maybe
import Control.Concurrent
import Control.Monad
import Data.Proxy
import Data.List
import Data.Default
import System.Process
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text.Encoding as T
import qualified Data.Text as T

import qualified CDP as CDP

main :: IO ()
main = do
    putStrLn "Starting CDP example"
    CDP.runClient def printPDF

targets :: CDP.Handle CDP.Event -> IO ()
targets handle = do
    ti <- head . CDP.targetGetTargetsTargetInfos <$> CDP.targetGetTargets handle
    let tid = CDP.targetTargetInfoTargetId ti
    r <- CDP.targetAttachToTarget handle $ CDP.PTargetAttachToTarget tid (Just True)
    print r
    browser handle 

browser :: CDP.Handle CDP.Event -> IO ()
browser handle = print =<< CDP.browserGetVersion handle

subUnsub :: CDP.Handle CDP.Event -> IO ()
subUnsub handle = do
    CDP.subscribe handle (print . CDP.pageWindowOpenUrl)
    CDP.pageEnable handle
    CDP.unsubscribe handle (Proxy :: Proxy CDP.PageWindowOpen)

    forever $ do
        threadDelay 1000

printPDF :: CDP.Handle CDP.Event -> IO ()
printPDF handle = do
    -- send the Page.printToPDF command
    r <- CDP.pagePrintToPdf handle $
            CDP.PPagePrintToPdf Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing $
                CDP.PPagePrintToPdfTransferModeReturnAsStream

    -- obtain stream handle from which to read pdf data
    let streamHandle = fromJust . CDP.pagePrintToPdfStream $ r

    -- read pdf data 24000 bytes at a time, this could be refactored to
    -- properly take the 'encoded' flag into account and produce a lazy
    -- bytestring
    let params = CDP.PIoRead streamHandle Nothing $ Just 24000
    reads <- whileTrue (not . CDP.ioReadEof) $ CDP.ioRead handle params
    let dat = map (Base64.decodeLenient . T.encodeUtf8 . T.pack . CDP.ioReadData) reads
    B.writeFile "mypdfs.pdf" $ B.concat dat

whileTrue :: Monad m => (a -> Bool) -> m a -> m [a]
whileTrue f act = do
    a <- act
    if f a
        then pure . (a :) =<< whileTrue f act
        else pure [a]
