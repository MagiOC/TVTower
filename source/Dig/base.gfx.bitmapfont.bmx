SuperStrict
Import BRL.Max2D
Import BRL.Map
Import brl.FreeTypeFont 'to load from truetype
Import "base.util.rectangle.bmx"
Import "base.gfx.sprite.bmx"
Import "base.gfx.spriteatlas.bmx"




CONST SHADOWFONT:INT = 256
CONST GRADIENTFONT:INT = 512

Type TBitmapFontManager
	Field baseFont:TBitmapFont
	Field baseFontBold:TBitmapFont
	Field baseFontItalic:TBitmapFont
	Field baseFontSmall:TBitmapFont
	Field _defaultFont:TBitmapFont
	Field List:TList = CreateList()
	Global systemFont:TBitmapFont
	Global _instance:TBitmapFontManager


	Method New()
		_instance = self
	End Method


	Function GetInstance:TBitmapFontManager()
		if not _instance then _instance = new TBitmapFontManager
		return _instance
	End Function


	Method GetDefaultFont:TBitmapFont()
		'instead of doing it in "new" (no guarantee that graphicsmode
		'is set up already)
		if not systemFont then systemFont = TBitmapFont.Create("SystemFont", "", 12, SMOOTHFONT)

		'if no default font was set, return the system font
		if not _defaultFont then return systemFont

		return _defaultFont
	End Method


	Method Get:TBitmapFont(name:String, size:Int=-1, style:Int=-1)
		name = lower(name)
		style :| SMOOTHFONT

		Local defaultFont:TBitmapFont = GetDefaultFont()

		'no details given: return default font
		If name = "default" And size = -1 And style = -1 Then Return defaultFont
		'no size given: use default font size
		If size = -1 Then size = defaultFont.FSize
		'no style given: use default font style
		If style = -1 Then style = defaultFont.FStyle 'Else style = style | SMOOTHFONT

		'if the font wasn't found, use the defaultFont-fontfile to load this style
		Local defaultFontFile:String = defaultFont.FFile
		For Local Font:TBitmapFont = EachIn Self.List
			If Font.FName = name And Font.FStyle = style Then defaultFontFile = Font.FFile
			If Font.FName = name And Font.FSize = size And Font.FStyle = style Then Return Font
		Next
		Return Add(name, defaultFontFile, size, style)
	End Method


	Method Copy:TBitmapFont(sourceName:string, copyName:string, size:int=-1, style:int=-1)
		local sourceFont:TBitmapFont = Get(sourceName, size, style)
		Local newFont:TBitmapFont = TBitmapFont.Create(sourceFont.fName, sourceFont.fFile, sourceFont.fSize, sourceFont.fStyle)
		List.AddLast(newFont)
		return newFont
	End Method


	Method Add:TBitmapFont(name:String, file:String, size:Int, style:Int=0)
		name = lower(name)
		style :| SMOOTHFONT

		local defaultFont:TBitmapFont = GetDefaultFont()
		If size = -1 Then size = defaultFont.FSize
		If style = -1 Then style = defaultFont.FStyle
		If file = "" Then file = defaultFont.FFile

		Local Font:TBitmapFont = TBitmapFont.Create(name, file, size, style)
		List.AddLast(Font)

		'set default fonts if not done yet
		if _defaultFont = null then _defaultFont = Font
		if baseFont = null then baseFont = Font

		Return Font
	End Method
End Type

'===== CONVENIENCE ACCESSORS =====
'convenience instance getter
Function GetBitmapFontManager:TBitmapFontManager()
	return TBitmapFontManager.GetInstance()
End Function

'===== CONVENIENCE ACCESSORS =====
'not really needed - but for convenience to avoid direct call to the
'instance getter GetBitmapFontManager()
Function GetBitmapFont:TBitmapfont(name:string, size:Int=-1, style:Int=-1)
	Return TBitmapFontManager.GetInstance().Get(name, size, style)
End Function



Type TBitmapFontChar
	Field area:TRectangle
	Field charWidth:float
	Field img:TImage


	Method Init:TBitmapFontChar(img:TImage, x:int,y:int,w:Int, h:int, charWidth:float)
		self.img = img
		self.area = new TRectangle.Init(x, y, w, h)
		self.charWidth = charWidth
		Return self
	End Method
End Type




Type TBitmapFont
	Field FName:string = ""			'identifier
	Field FFile:string = ""			'source path
	Field FSize:int = 0				'size of this font
	Field FStyle:int = 0			'style used in this font
	Field FImageFont:TImageFont		'the original imagefont

	Field chars:TMap = CreateMap()
	Field charsSprites:Tmap	= CreateMap()
	field spriteSet:TSpritePack
	Field MaxSigns:Int = 256
	Field ExtraChars:String = "€…"
	Field gfx:TMax2dGraphics
	Field uniqueID:string =""
	Field displaceY:float=100.0
	Field lineHeightModifier:float = 0.2	'modifier * lineheight gets added at the end
	Field drawAtFixedPoints:int = true		'whether to use ints or floats for coords
	Field _charsEffectFunc:TBitmapFontChar(font:TBitmapFont, charKey:string, char:TBitmapFontChar, config:TData)[]
	Field _charsEffectFuncConfig:TData[]
	Field _pixmapFormat:int = PF_A8			'by default this is 8bit alpha only
	Field _maxCharHeight:int = 0
	Field _maxCharHeightAboveBaseline:int = 0
	Field _hasEllipsis:int = -1

	global drawToPixmap:TPixmap = null
'DISABLECACHE	global ImageCaches:TMap = CreateMap()
	global eventRegistered:int = 0


	Function Create:TBitmapFont(name:String, url:String, size:Int, style:Int)
		Local obj:TBitmapFont = New TBitmapFont
		obj.FName = name
		obj.FFile = url
		obj.FSize = size
		obj.FStyle = style
		obj.uniqueID = name+"_"+url+"_"+size+"_"+style
		obj.gfx = tmax2dgraphics.Current()
		obj.FImageFont = LoadTrueTypeFont(url, size, style)
		If not obj.FImageFont
			'get system/current font
			obj.FImageFont = GetImageFont()
		endif
		If not obj.FImageFont
			Throw ("TBitmapFont.Create: font ~q"+url+"~q not found.")
			Return Null 'font not found
		endif

		'create spriteset
		obj.spriteSet = new TSpritePack.Init(null, obj.uniqueID+"_charmap")

		'generate a charmap containing packed rectangles where to store images
		obj.InitFont()

		'listen to App-timer
'DISABLECACHE		EventManager.registerListener( "App.onUpdate", 	TEventListenerRunFunction.Create(TBitmapFont.onUpdateCaches) )

		Return obj
	End Function


	Method SetCharsEffectFunction(position:int, _func:TBitmapFontChar(font:TBitmapFont, charKey:string, char:TBitmapFontChar, config:TData), config:TData=null)
		position :-1 '0 based
		if _charsEffectFunc.length <= position
			_charsEffectFunc = _charsEffectFunc[..position+1]
			_charsEffectFuncConfig = _charsEffectFuncConfig[..position+1]
		endif
		_charsEffectFunc[position] = _func
		_charsEffectFuncConfig[position] = config
	End Method


	'overrideable method
	Method ApplyCharsEffect(config:TData=null)
		'if instead of overriding a function was provided - use this
		if _charsEffectFunc.length > 0
			for local charKey:string = eachin chars.keys()
				local char:TBitmapFontChar = TBitmapFontChar(chars.ValueForKey(charKey))

				'manipulate char
				local _func:TBitmapFontChar(font:TBitmapFont, charKey:string, char:TBitmapFontChar, config:TData)
				local _config:TData
				for local i:int = 0 to _charsEffectFunc.length-1
					_func = _charsEffectFunc[i]
					_config = _charsEffectFuncConfig[i]
					if not _config then _config = config
					char = _func(self, charKey, char, _config)
				Next
				'overwrite char
				chars.Insert(charKey, char)
			Next
		endif

		'else do nothing by default
	End Method


	'generate a charmap containing packed rectangles where to store images
	Method InitFont(config:TData=null )
		'1. load chars
		LoadCharsFromImgFont()
		'2. Process the characters (add shadow, gradients, ...)
		ApplyCharsEffect(config)
		'3. store them into a packed (optimized) charmap
		'   -> creates a 8bit alpha'd image (grayscale with alpha ...)
		CreateCharmapImage( CreateCharmap(1) )
	End Method


	'load glyphs of an imagefont as TBitmapFontChar into a char-TMap
	Method LoadCharsFromImgFont(imgFont:TImageFont=null)
		if imgFont = null then imgFont = FImageFont
		Local glyph:TImageGlyph
		Local glyphCount:Int = imgFont.CountGlyphs()
		Local n:int
		For Local i:Int = 0 Until MaxSigns
			n = imgFont.CharToGlyph(i)
			If n < 0 or n > glyphCount then Continue
			glyph = imgFont.LoadGlyph(n)
			If not glyph then continue

			'base displacement calculated with A-Z (space between TOPLEFT of 'ABCDE' and TOPLEFT of 'acen'...)
			if i >= 65 AND i < 95 then displaceY = Min(displaceY, glyph._y)
			chars.insert(string(i), new TBitmapFontChar.Init(glyph._image, glyph._x, glyph._y,glyph._w,glyph._h, glyph._advance))
		Next
		For Local charNum:Int = 0 Until ExtraChars.length
			n = imgFont.CharToGlyph( ExtraChars[charNum] )
			If n < 0 or n > glyphCount then Continue
			glyph = imgFont.LoadGlyph(n)
			If not glyph then continue
			chars.insert(string(ExtraChars[charNum]) , new TBitmapFontChar.Init(glyph._image, glyph._x, glyph._y,glyph._w,glyph._h, glyph._advance) )
		Next
	End Method


	'create a charmap-atlas with information where to optimally store
	'each char
	Method CreateCharmap:TSpriteAtlas(spaceBetweenChars:int=0)
		local charmap:TSpriteAtlas = TSpriteAtlas.Create(64,64)
		local bitmapFontChar:TBitmapFontChar
		for local charKey:string = eachin chars.keys()
			bitmapFontChar = TBitmapFontChar(chars.ValueForKey(charKey))
			if not bitmapFontChar then continue
			charmap.AddElement(charKey, bitmapFontChar.area.GetW()+spaceBetweenChars,bitmapFontChar.area.GetH()+spaceBetweenChars ) 'add box of char and package atlas
		Next
		return charmap
	End Method


	'create an image containing all chars
	'the charmap-atlas contains information where to store each character
	Method CreateCharmapImage(charmap:TSpriteAtlas)
		local pix:TPixmap = CreatePixmap(charmap.w,charmap.h, _pixmapFormat) ; pix.ClearPixels(0)
		'loop through atlas boxes and add chars
		For local charKey:string = eachin charmap.elements.Keys()
			local rect:TRectangle = TRectangle(charmap.elements.ValueForKey(charKey))
			'skip missing data
			if not chars.ValueForKey(charKey) then continue
			if not TBitmapFontChar(chars.ValueForKey(charKey)).img then continue

			'draw char image on charmap
			'print "adding "+charKey + " = "+chr(int(charKey))
			local charPix:TPixmap = LockImage(TBitmapFontChar(chars.ValueForKey(charKey)).img)
'			If charPix.format <> 2 Then charPix.convert(PF_A8) 'make sure the pixmaps are 8bit alpha-format
			DrawImageOnImage(charPix, pix, rect.GetX(), rect.GetY())
			UnlockImage(TBitmapFontChar(chars.ValueForKey(charKey)).img)
			' es fehlt noch charWidth - extraTyp?

			charsSprites.insert(charKey, new TSprite.Init(spriteSet, charKey, rect, null, 0))
		Next
		'set image to sprite pack
		spriteSet.image = LoadImage(pix)
	End Method


	'Returns whether this font has a visible ellipsis char ("…")
	Method HasEllipsis:int()
		if _hasEllipsis = -1 then _hasEllipsis = GetWidth(chr(8230))
		return _hasEllipsis
	End Method


	Method GetEllipsis:string()
		if hasEllipsis() then return chr(8230)
		return "..."
	End Method


	Method getMaxCharHeight:int(includeBelowBaseLine:int=True)
		if includeBelowBaseLine
			if _maxCharHeight = 0 then _maxCharHeight = getHeight("gQ'_")
			return _maxCharHeight
		else
			if _maxCharHeightAboveBaseline = 0 then _maxCharHeightAboveBaseline = getHeight("abCDE")
			return _maxCharHeightAboveBaseline
		endif
	End Method


	Method getWidth:Float(text:String)
		return draw(text,0,0,null,0).getX()
	End Method


	Method getHeight:Float(text:String)
		return draw(text,0,0,null,0).getY()
	End Method


	Method getBlockHeight:Float(text:String, w:Float, h:Float)
		return drawBlock(text, 0,0,w,h, null, null, 0, 0).getY()
	End Method


	'render to target pixmap/image/screen
	Function setRenderTarget:int(target:object=null)
		'render to screen
		if not target
			drawToPixmap = null
			return TRUE
		endif

		if TImage(target)
			drawToPixmap = LockImage(TImage(target))
		elseif TPixmap(target)
			drawToPixmap = TPixmap(target)
		endif
	End Function


	'splits a given text into an array of lines
	'splitting is done on "spaces", "-"
	'or in the middle of a word if "nicelyTruncateLastLine" is "FALSE"
	Method TextToMultiLine:string[](text:string, w:float, h:float, lineHeight:float, nicelyTruncateLastLine:int=TRUE)
		Local fittingChars:int	= 0
		Local processedChars:Int= 0
		Local paragraphs:string[]	= text.replace(chr(13), "~n").split("~n")
		'the lines to output at the end
		Local lines:string[]= null
		'how many space is left to draw?
		local heightLeft:float	= h
		'are we limited in height?
		local limitHeight:int = (heightLeft <> -1)

		'for each line/paragraph
		For Local i:Int= 0 To paragraphs.length-1
			'skip paragraphs if no space was left
			if limitHeight and heightLeft < lineHeight then continue

			local line:string = paragraphs[i]

			'process each line - and if needed add a line break
			repeat
				'the part of the line which has to get processed at that moment
				local linePartial:string = line
				local breakPosition:int = line.length
				'whether to skip the next char of a new line
				local skipNextChar:int	= FALSE

				'copy the line to do processing and shortening
				linePartial = line

				'as long as the part of the line does not fit into
				'the given width, we have to search for linebreakers
				while self.getWidth(linePartial) >= w and linePartial.length >0
					'whether we found a break position by a rule
					local FoundBreakPosition:int = FALSE

					'search for "nice" linebreak:
					'- if not on last line
					'- if enforced to do so ("nicelyTruncateLastLine")
					if i < (paragraphs.length-1) or nicelyTruncateLastLine
						'search for the "most right" position of a linebreak
						For local charPos:int = 0 To linePartial.length-1
							'special line break rules (spaces, -, ...)
							If linePartial[charPos] = Asc(" ")
								breakPosition = charPos
								FoundBreakPosition=TRUE
							endif
							If linePartial[charPos] = Asc("-")
								breakPosition = charPos
								FoundBreakPosition=TRUE
							endif
						Next
					endif

					'if no line break rule hit, use a "cut" in the middle of a word
					if not FoundBreakPosition then breakPosition = Max(0, linePartial.length-1 -1)

					'if it is a " "-space, we have to skip it
					if linePartial[breakPosition] = ASC(" ")
						skipNextChar = TRUE 'aka delete the " "
					endif


					'cut off the part AFTER the breakposition
					linePartial = linePartial[..breakPosition]
				wend
				'add that line to the lines to draw
				lines :+ [linePartial]

				heightLeft :- lineHeight


				'strip the processed part from the original line
				line = line[linePartial.length..]

				if skipNextChar then line = line[Min(1, line.length)..]
			'until no text left, or no space left for another line
			until line.length = 0  or (limitHeight and heightLeft < lineHeight)

			'if the height was not enough - add a "..."
			if line.length > 0
				'get the line BEFORE
				local currentLine:string = lines[lines.length-1]
				'check whether we have to subtract some chars for the "..."
				local ellipsisChar:string = GetEllipsis()
				if getWidth(currentLine + ellipsisChar) > w
					currentLine = currentLine[.. currentLine.length-3] + ellipsisChar
				else
					currentLine = currentLine[.. currentLine.length] + ellipsisChar
				endif
				lines[lines.length-1] = currentLine
			endif
		Next

		return lines
	End Method


	Method drawBlock:TPoint(text:String, x:Float, y:Float, w:Float, h:Float, alignment:TPoint=null, color:TColor=null, style:int=0, doDraw:int = 1, special:float=1.0, nicelyTruncateLastLine:int=TRUE)
		'use special chars (instead of text) for same height on all lines
		Local alignedX:float	= 0.0
		Local lineHeight:float	= getMaxCharHeight()
		Local lines:string[] = TextToMultiLine(text, w, h, lineHeight, nicelyTruncateLastLine)

		local blockHeight:Float = lineHeight * lines.length
		if lines.length > 1
			'add the lineHeightModifier for all lines but the first or single one
			blockHeight :+ lineHeight * lineHeightModifier
		endif

		'move along y according alignment
		'-> aligned top: no change
		'-> aligned bottom: move down by unused space so last line ends at Y + h
		'-> aligned inbetween: move accordingly
		if alignment
			'empty space = height - (..)
			'so alignTop = add 0 of that space, alignBottom = add 100% of that space
			if alignment.GetY() <> ALIGN_TOP
				y :+ alignment.GetY() * (h - blockHeight)
			endif
		endif

		local startY:Float = y
		For local i:int = 0 to lines.length-1
			'only align when drawing
			If doDraw
				if alignment and alignment.GetX() <> ALIGN_LEFT
					alignedX = x + alignment.GetX() * (w - getWidth(lines[i]))
				else
					alignedX = x
				endif
			EndIf
			local p:TPoint = drawStyled( lines[i], alignedX, y, color, style, doDraw,special)

			y :+ Max(lineHeight, p.y)
			'add extra spacing _between_ lines
			If lines.length > 1 and i < lines.length-1
				y :+ lineHeight * lineHeightModifier
			Endif
		Next

		return new TPoint.Init(w, y - startY)
	End Method


	Method drawStyled:TPoint(text:String,x:Float,y:Float, color:TColor=null, style:int=0, doDraw:int=1, special:float=-1.0)
		if drawAtFixedPoints
			x = int(x)
			y = int(y)
		endif

		local height:float = 0.0
		local width:float = 0.0

		'backup old color
		local oldColor:TColor
		if doDraw and color then oldColor = new TColor.Get()

		'emboss
		if style = 1
			height:+ 1
			if doDraw
				if special <> -1.0
					SetAlpha float(special * oldColor.a)
				else
					SetAlpha float(0.75 * oldColor.a)
				endif
				draw(text, x, y+1, TColor.clWhite)
			endif
		'shadow
		else if style = 2
			height:+ 1
			width:+1
			if doDraw
				if special <> -1.0 then SetAlpha special*oldColor.a else SetAlpha 0.5*oldColor.a
				draw(text, x+1,y+1, TColor.clBlack)
			endif
		'glow
		else if style = 3
			if doDraw
				SetColor 0,0,0
				if special <> -1.0 then SetAlpha 0.5*oldColor.a else SetAlpha 0.25*oldColor.a
				draw(text, x-2,y)
				draw(text, x+2,y)
				draw(text, x,y-2)
				draw(text, x,y+2)
				if special <> -1.0 then SetAlpha special*oldColor.a else SetAlpha 0.5*oldColor.a
				draw(text, x+1,y+1)
				draw(text, x-1,y-1)
			endif
		endif

		if oldColor then SetAlpha oldColor.a
		local result:TPoint = draw(text,x,y, color, doDraw)

		if oldColor then oldColor.SetRGBA()
		return result
	End Method


	Method drawWithBG:TPoint(value:String, x:Int, y:Int, bgAlpha:Float = 0.3, bgCol:Int = 0, style:int=0)
		Local OldAlpha:Float = GetAlpha()
		Local color:TColor = new TColor.Get()
		local dimension:TPoint = drawStyled(value,0,0, null, style,0)
		SetAlpha bgAlpha
		SetColor bgCol, bgCol, bgCol
		DrawRect(x, y, dimension.GetX(), dimension.GetY())
		color.setRGBA()
		return drawStyled(value, x, y, color, style)
	End Method


	'can adjust used font or color
	Method ProcessCommand:int(command:string, payload:string, font:TBitmapFont var , color:TColor var , colorOriginal:TColor, styleDisplaceY:int var)
		if color
			if command = "color"
				local colors:string[] = payload.split(",")
				if colors.length >= 3
					color.r = int(colors[0])
					color.g = int(colors[1])
					color.b = int(colors[2])
					if colors.length >= 4
						color.a = int(colors[3]) / 255.0
					else
						color.a = 1.0
					endif
				endif
				color.SetRGBA()
			endif
			if command = "/color"
				color.r = colorOriginal.r
				color.g = colorOriginal.g
				color.b = colorOriginal.b
				color.a = colorOriginal.a
				color.SetRGBA()
			endif
		endif

		if command = "b" then font = GetBitmapFontManager().Get(FName, FSize, BOLDFONT)
		if command = "/b" then font = self

		if command = "bi" then font = GetBitmapFontManager().Get(FName, FSize, BOLDFONT | ITALICFONT)
		if command = "/bi" then font = self

		if command = "i" then font = GetBitmapFontManager().Get(FName, FSize, ITALICFONT)
		if command = "/i" then font = self

		'adjust line height if another font is selected
		if font <> self
			styleDisplaceY = (getMaxCharHeight() - font.getMaxCharHeight())
		else
			'reset displace
			styleDisplaceY = 0
		endif
		if not font then font = self
	End Method


	Method draw:TPoint(text:String,x:Float,y:Float, color:TColor=null, doDraw:int=TRUE)
		local width:float = 0.0
		local height:float = 0.0
		local textLines:string[]	= text.replace(chr(13), "~n").split("~n")
		local currentLine:int = 0
		local oldColor:TColor
		if doDraw
			oldColor = new TColor.Get()
			if not color
				color = oldColor.copy()
			else
				'when drawing to a pixmap, take screen alpha into consideration
				if drawToPixmap
					'create a copy to not modify the original
					color = color.copy()
					color.a :* oldColor.a
				endif
			endif
			'black text is default
'			if not color then color = TColor.Create(0,0,0)
			if color then color.SetRGB()

		endif
		'set the lineHeight before the "for-loop" so it has a set
		'value if a line "in the middle" just consists of spaces or nothing
		'-> allows double-linebreaks

		'control vars
		local controlChar:int = asc("|")
		local controlCharEscape:int = asc("\")
		local controlCharStarted:int = FALSE
		local currentControlCommandPayloadSeparator:string = "="
		local currentControlCommand:string = ""
		local currentControlCommandPayload:string = ""

		local lineHeight:int = 0
		local char:string = ""
		local charBefore:int
		local font:TBitmapFont = self 'by default this font is responsible
		local colorOriginal:TColor = null
		local rotation:int = GetRotation()
		local sprite:TSprite
		local styleDisplaceY:int = 0
		For text:string = eachin textLines
			'except first line (maybe only one line) - add extra spacing between lines
			if currentLine > 0 then height:+ ceil( lineHeight* font.lineHeightModifier )

			currentLine:+1

			local lineWidth:int = 0

			For Local i:Int = 0 Until text.length
				char = text[i]


				'check for controls
				if controlCharStarted
					'receiving command
					if char <> controlChar
						currentControlCommand:+ chr(int(char))
					'receive stopper
					else
						controlCharStarted = FALSE
						local commandData:string[] = currentControlCommand.split(currentControlCommandPayloadSeparator)
						currentControlCommand = commandData[0]
						if commandData.length>1 then currentControlCommandPayload = commandData[1]

						if color and not colorOriginal then colorOriginal = color.copy()
						ProcessCommand(currentControlCommand, currentControlCommandPayload, font, color, colorOriginal, styleDisplaceY)
						'reset
						currentControlCommand = ""
						currentControlCommandPayload = ""
					endif
					'skip char
					continue
				endif

				'someone wants style the font
				if char = controlChar and charBefore <> controlCharEscape
					controlCharStarted = 1 - controlCharStarted
					'skip char
					charBefore = int(char)
					continue
				endif
				'skip drawing the escape char if we are escaping the command char
				if char = controlCharEscape and i < text.length-1 and text[i+1] = controlChar
					charBefore = int(char)
					continue
				endif

				Local bm:TBitmapFontChar = TBitmapFontChar( font.chars.ValueForKey(char) )
				if bm <> null
					Local tx:Float = bm.area.GetX() * gfx.tform_ix + bm.area.GetY() * gfx.tform_iy
					Local ty:Float = bm.area.GetX() * gfx.tform_jx + bm.area.GetY() * gfx.tform_jy
					'drawable ? (> 32)
					if text[i] > 32
						lineHeight = MAX(lineHeight, bm.area.GetH())
						if doDraw
							sprite = TSprite(font.charsSprites.ValueForKey(char))
							if sprite
								if drawToPixmap
									sprite.DrawOnImage(drawToPixmap, x+lineWidth+tx,y+height+ty+styleDisplaceY - font.displaceY, color)
								else
									sprite.Draw(x+lineWidth+tx,y+height+ty+styleDisplaceY - font.displaceY)
								endif
							endif
						endif
					endif
					if rotation = -90
						height:- MIN(lineHeight, bm.area.GetW())
					elseif rotation = 90
						height:+ MIN(lineHeight, bm.area.GetW())
					elseif rotation = 180
						lineWidth :- bm.charWidth * gfx.tform_ix
					else
						lineWidth :+ bm.charWidth * gfx.tform_ix
					endif
				EndIf

				charBefore = int(char)
			Next
			width = max(width, lineWidth)
			height:+lineHeight
			'add extra spacing _between_ lines
			'not done when only 1 line available or on last line
			if currentLine < textLines.length
				height:+ ceil( lineHeight* font.lineHeightModifier )
			endif
		Next

		'restore color
		if doDraw then oldColor.SetRGB()

		return new TPoint.Init(width, height)
	End Method

rem
	Method drawfixed(text:String,x:Float,y:Float)
		local color:TColor = new TColor.Get()

		For Local i:Int = 0 Until text.length
			Local bm:TBitmapFontChar = TBitmapFontChar(self.chars.ValueForKey(string(text[i]-32)))
			if bm <> null
				Local tx:Float = bm.area.GetX() * gfx.tform_ix + bm.area.GetY() * gfx.tform_iy
				Local ty:Float = bm.area.GetX() * gfx.tform_jx + bm.area.GetY() * gfx.tform_jy
				local sprite:TSprite = TSprite(self.charsSprites.ValueForKey(string(text[i]-32)))
				if sprite <> null
					if self.drawToPixmap
						sprite.DrawOnPixmap(self.drawToPixmap, x+tx,y+ty, color)
					else
						sprite.Draw(x+tx,y+ty)
					endif
				endif
				x :+ bm.charWidth
			endif
		Next
	End Method
endrem

Rem
DISABLECACHE
	Function onUpdateCaches(triggerEvent:TEventBase)
		For local key:string = eachin TBitmapFont.ImageCaches.Keys()
			local cache:TImageCache = TImageCache(TBitmapFont.ImageCaches.ValueForKey(key))
			if cache and not cache.isAlive() then TBitmapFont.ImageCaches.Remove(key)
		Next
	End Function
EndRem
End Type



' - max2d/max2d.bmx -> loadimagefont
' - max2d/imagefont.bmx TImageFont.Load ->
Function LoadTrueTypeFont:TImageFont( url:Object,size:int,style:int )
	Local src:TFont = TFreeTypeFont.Load( String( url ), size, style )
	If Not src Return null

	Local font:TImageFont=New TImageFont
	font._src_font=src
	font._glyphs=New TImageGlyph[src.CountGlyphs()]
	If style & SMOOTHFONT then font._imageFlags=FILTEREDIMAGE|MIPMAPPEDIMAGE

	Return font
End Function