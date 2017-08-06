module Text.Wrap
  ( WrapSettings(..)
  , defaultWrapSettings

  , wrapTextToLines
  , wrapText
  )
where

import Data.Monoid ((<>))
import Data.Char (isSpace)
import qualified Data.Text as T

-- | Settings to control how wrapping is performed.
data WrapSettings =
    WrapSettings { preserveIndentation :: Bool
                 -- ^ Whether to indent new lines created by wrapping
                 -- when their original line was indented.
                 , breakLongWords :: Bool
                 -- ^ Whether to break in the middle of the first word
                 -- on a line when that word exceeds the wrapping width.
                 }
                 deriving (Eq, Show, Read)

defaultWrapSettings :: WrapSettings
defaultWrapSettings =
    WrapSettings { preserveIndentation = False
                 , breakLongWords = False
                 }

-- | Wrap text at the specified width. Newlines and whitespace in the
-- input text are preserved. Returns the lines of text in wrapped form.
-- New lines introduced due to wrapping will have leading whitespace
-- stripped.
wrapTextToLines :: WrapSettings -> Int -> T.Text -> [T.Text]
wrapTextToLines settings amt s =
    concat $ fmap (wrapLine settings amt) $ T.lines s

-- | Like 'wrapTextToLines', but returns the wrapped text reconstructed
-- with newlines inserted at wrap points.
wrapText :: WrapSettings -> Int -> T.Text -> T.Text
wrapText settings amt s =
    T.intercalate (T.pack "\n") $ wrapTextToLines settings amt s

data Token = WS T.Text | NonWS T.Text
           deriving (Show)

tokenLength :: Token -> Int
tokenLength = T.length . tokenContent

tokenContent :: Token -> T.Text
tokenContent (WS t) = t
tokenContent (NonWS t) = t

-- | Tokenize text into whitespace and non-whitespace chunks.
tokenize :: T.Text -> [Token]
tokenize t | T.null t = []
tokenize t =
    let leadingWs = T.takeWhile isSpace t
        leadingNonWs = T.takeWhile (not . isSpace) t
        tok = if T.null leadingWs
              then NonWS leadingNonWs
              else WS leadingWs
    in tok : tokenize (T.drop (tokenLength tok) t)

-- | Wrap a single line of text into a list of lines that all satisfy
-- the wrapping width.
wrapLine :: WrapSettings
         -- ^ Settings.
         -> Int
         -- ^ The wrapping width.
         -> T.Text
         -- ^ A single line of text.
         -> [T.Text]
wrapLine settings limit t =
    let go _ []     = [T.empty]
        go _ [WS _] = [T.empty]
        go lim ts =
            let (firstLine, maybeRest) = breakTokens settings lim ts
                firstLineText = T.stripEnd $ T.concat $ fmap tokenContent firstLine
            in case maybeRest of
                Nothing -> [firstLineText]
                Just rest -> firstLineText : go lim rest
        (indent, modifiedText) = if preserveIndentation settings
                         then let i = T.takeWhile isSpace t
                              in (i, T.drop (T.length i) t)
                         else (T.empty, t)
        result = go (limit - T.length indent) (tokenize modifiedText)
    in (indent <>) <$> result

-- | Break a token sequence so that all tokens up to but not exceeding
-- a length limit are included on the left, and if any remain on the
-- right, return Just those too (or Nothing if there weren't any). If
-- this breaks a sequence at at point where the next token after the
-- break point is whitespace, that whitespace token is removed.
breakTokens :: WrapSettings -> Int -> [Token] -> ([Token], Maybe [Token])
breakTokens _ _ [] = ([], Nothing)
breakTokens settings limit ts =
    -- Take enough tokens until we reach the point where taking more
    -- would exceed the line length.
    let go _ []     = ([], [])
        -- If the line starts with a non-whitespace token that exceeds
        -- the limit, we either keep it (breakLongWords = False) or
        -- break it (breakLongWords = True).
        go 0 (t@(NonWS _):toks) =
            if tokenLength t <= limit
            then ([t], toks)
            else if not $ breakLongWords settings
                 then ([t], toks)
                 else let (h, tl) = T.splitAt limit (tokenContent t)
                      in ([NonWS h], NonWS tl : toks)
        -- The general case: check to see whether the next token exceeds
        -- the limit. If so, bump it to the next line and terminate.
        -- Otherwise keep it and continue to the next token.
        go acc (tok:toks) =
            if tokenLength tok + acc <= limit
            then let (nextAllowed, nextDisallowed) = go (acc + tokenLength tok) toks
                 in (tok : nextAllowed, nextDisallowed)
            else case tok of
                     WS _ -> ([], toks)
                     NonWS _ ->
                         if acc == 0
                         then ([tok], toks)
                         else ([], tok:toks)

        -- Allowed tokens are the ones we keep on this line. The rest go
        -- on the next line, to be wrapped again.
        (allowed, disallowed') = go 0 ts
        disallowed = maybeTrim disallowed'

        -- Trim leading whitespace on wrapped lines.
        maybeTrim [] = []
        maybeTrim (WS _:toks) = toks
        maybeTrim toks = toks

        result = if null disallowed
                 then (allowed, Nothing)
                 else (allowed, Just disallowed)
    in result
