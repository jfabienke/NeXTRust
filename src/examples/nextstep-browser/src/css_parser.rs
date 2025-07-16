// CSS Parser module for NeXTSTEP Browser
// Handles CSS parsing with support for NeXT's advanced typography

use std::collections::HashMap;
use cssparser::{Parser, ParserInput, Token, ToCss};

#[derive(Debug, Clone)]
pub struct StyleSheet {
    pub rules: Vec<CSSRule>,
}

#[derive(Debug, Clone)]
pub struct CSSRule {
    pub selectors: Vec<Selector>,
    pub declarations: Vec<Declaration>,
}

#[derive(Debug, Clone)]
pub struct Selector {
    pub specificity: u32,
    pub parts: Vec<SelectorPart>,
}

#[derive(Debug, Clone)]
pub enum SelectorPart {
    Tag(String),
    Class(String),
    Id(String),
    Universal,
    Descendant,
    Child,
}

#[derive(Debug, Clone)]
pub struct Declaration {
    pub property: String,
    pub value: CSSValue,
    pub important: bool,
}

#[derive(Debug, Clone)]
pub enum CSSValue {
    Length(f32, LengthUnit),
    Color(Color),
    String(String),
    Number(f32),
    Percentage(f32),
    Keyword(String),
    FontFamily(Vec<String>),
}

#[derive(Debug, Clone, Copy)]
pub enum LengthUnit {
    Px, Pt, Em, Rem, Percent, Vh, Vw
}

#[derive(Debug, Clone, Copy)]
pub struct Color {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

impl Color {
    pub const BLACK: Color = Color { r: 0.0, g: 0.0, b: 0.0, a: 1.0 };
    pub const WHITE: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 };
    pub const RED: Color = Color { r: 1.0, g: 0.0, b: 0.0, a: 1.0 };
    pub const GREEN: Color = Color { r: 0.0, g: 1.0, b: 0.0, a: 1.0 };
    pub const BLUE: Color = Color { r: 0.0, g: 0.0, b: 1.0, a: 1.0 };
}

#[derive(Debug, Clone)]
pub struct ComputedStyle {
    // Typography
    pub font_family: Vec<String>,
    pub font_size: f32,
    pub font_weight: FontWeight,
    pub font_style: FontStyle,
    pub line_height: f32,
    pub text_align: TextAlign,
    
    // Colors
    pub color: Color,
    pub background_color: Option<Color>,
    
    // Box model
    pub margin: BoxModel,
    pub padding: BoxModel,
    pub border: BorderStyle,
    
    // Layout
    pub display: DisplayType,
    pub position: PositionType,
    pub width: Option<Length>,
    pub height: Option<Length>,
    
    // NeXT-specific
    pub postscript_font: Option<String>,
    pub text_rendering: TextRendering,
}

#[derive(Debug, Clone, Copy)]
pub enum FontWeight {
    Normal, Bold, Bolder, Lighter, Weight(u16)
}

#[derive(Debug, Clone, Copy)]
pub enum FontStyle {
    Normal, Italic, Oblique
}

#[derive(Debug, Clone, Copy)]
pub enum TextAlign {
    Left, Right, Center, Justify
}

#[derive(Debug, Clone, Copy)]
pub struct BoxModel {
    pub top: f32,
    pub right: f32,
    pub bottom: f32,
    pub left: f32,
}

#[derive(Debug, Clone)]
pub struct BorderStyle {
    pub width: f32,
    pub style: BorderType,
    pub color: Color,
}

#[derive(Debug, Clone, Copy)]
pub enum BorderType {
    None, Solid, Dashed, Dotted
}

#[derive(Debug, Clone, Copy)]
pub enum DisplayType {
    Block, Inline, InlineBlock, None, Flex, Grid
}

#[derive(Debug, Clone, Copy)]
pub enum PositionType {
    Static, Relative, Absolute, Fixed
}

#[derive(Debug, Clone)]
pub enum Length {
    Px(f32),
    Percent(f32),
    Em(f32),
    Auto,
}

#[derive(Debug, Clone, Copy)]
pub enum TextRendering {
    Auto,
    OptimizeSpeed,
    OptimizeLegibility,  // Use NeXT's advanced typography
    GeometricPrecision,  // Use PostScript precision
}

impl Default for ComputedStyle {
    fn default() -> Self {
        ComputedStyle {
            font_family: vec!["Times".to_string(), "serif".to_string()],
            font_size: 16.0,
            font_weight: FontWeight::Normal,
            font_style: FontStyle::Normal,
            line_height: 1.2,
            text_align: TextAlign::Left,
            color: Color::BLACK,
            background_color: None,
            margin: BoxModel { top: 0.0, right: 0.0, bottom: 0.0, left: 0.0 },
            padding: BoxModel { top: 0.0, right: 0.0, bottom: 0.0, left: 0.0 },
            border: BorderStyle {
                width: 0.0,
                style: BorderType::None,
                color: Color::BLACK,
            },
            display: DisplayType::Block,
            position: PositionType::Static,
            width: None,
            height: None,
            postscript_font: None,
            text_rendering: TextRendering::OptimizeLegibility,
        }
    }
}

impl Default for BorderStyle {
    fn default() -> Self {
        BorderStyle {
            width: 0.0,
            style: BorderType::None,
            color: Color::BLACK,
        }
    }
}

pub fn parse_css(css: &str) -> Result<StyleSheet, ParseError> {
    let mut input = ParserInput::new(css);
    let mut parser = Parser::new(&mut input);
    let mut rules = Vec::new();
    
    while !parser.is_exhausted() {
        match parse_rule(&mut parser) {
            Ok(Some(rule)) => rules.push(rule),
            Ok(None) => {} // Skip empty rules
            Err(e) => {
                // Skip invalid rules but continue parsing
                eprintln!("CSS parse error: {:?}", e);
                parser.skip_whitespace();
            }
        }
    }
    
    Ok(StyleSheet { rules })
}

fn parse_rule(parser: &mut Parser) -> Result<Option<CSSRule>, ParseError> {
    parser.skip_whitespace();
    
    if parser.is_exhausted() {
        return Ok(None);
    }
    
    // Parse selectors
    let selectors = parse_selectors(parser)?;
    
    // Expect {
    parser.expect_curly_bracket_block()?;
    
    // Parse declarations inside block
    let declarations = parser.parse_nested_block(|parser| {
        parse_declarations(parser)
    })?;
    
    if selectors.is_empty() || declarations.is_empty() {
        Ok(None)
    } else {
        Ok(Some(CSSRule { selectors, declarations }))
    }
}

fn parse_selectors(parser: &mut Parser) -> Result<Vec<Selector>, ParseError> {
    let mut selectors = Vec::new();
    
    loop {
        parser.skip_whitespace();
        
        let mut parts = Vec::new();
        let mut specificity = 0;
        
        while !parser.is_exhausted() {
            match parser.next()? {
                Token::Ident(tag) => {
                    parts.push(SelectorPart::Tag(tag.to_string()));
                    specificity += 1;
                }
                Token::IDHash(id) => {
                    parts.push(SelectorPart::Id(id.to_string()));
                    specificity += 100;
                }
                Token::Delim('.') => {
                    if let Ok(Token::Ident(class)) = parser.next() {
                        parts.push(SelectorPart::Class(class.to_string()));
                        specificity += 10;
                    }
                }
                Token::Delim('*') => {
                    parts.push(SelectorPart::Universal);
                }
                Token::WhiteSpace(_) => {
                    parts.push(SelectorPart::Descendant);
                }
                Token::Delim('>') => {
                    parts.push(SelectorPart::Child);
                    parser.skip_whitespace();
                }
                Token::Comma => {
                    break;
                }
                Token::CurlyBracketBlock => {
                    // Put it back for the main parser
                    parser.reset(&parser.position());
                    break;
                }
                _ => break,
            }
        }
        
        if !parts.is_empty() {
            selectors.push(Selector { specificity, parts });
        }
        
        // Check if we should continue parsing selectors
        parser.skip_whitespace();
        match parser.next() {
            Ok(Token::Comma) => continue,
            Ok(Token::CurlyBracketBlock) => {
                parser.reset(&parser.position());
                break;
            }
            _ => break,
        }
    }
    
    Ok(selectors)
}

fn parse_declarations(parser: &mut Parser) -> Result<Vec<Declaration>, ParseError> {
    let mut declarations = Vec::new();
    
    parser.skip_whitespace();
    
    while !parser.is_exhausted() {
        // Parse property name
        let property = match parser.next()? {
            Token::Ident(prop) => prop.to_string(),
            _ => continue, // Skip invalid property
        };
        
        // Expect :
        parser.expect_colon()?;
        parser.skip_whitespace();
        
        // Parse value
        let mut values = Vec::new();
        let mut important = false;
        
        while !parser.is_exhausted() {
            match parser.next()? {
                Token::Semicolon => break,
                Token::Delim('!') => {
                    if let Ok(Token::Ident(imp)) = parser.next() {
                        if imp.eq_ignore_ascii_case("important") {
                            important = true;
                        }
                    }
                }
                token => {
                    if let Some(value) = parse_value(token, parser) {
                        values.push(value);
                    }
                }
            }
        }
        
        // Convert values to appropriate CSSValue
        if !values.is_empty() {
            let value = combine_values(&property, values);
            declarations.push(Declaration {
                property,
                value,
                important,
            });
        }
        
        parser.skip_whitespace();
    }
    
    Ok(declarations)
}

fn parse_value(token: &Token, parser: &mut Parser) -> Option<CSSValue> {
    match token {
        Token::Dimension { has_sign: _, value, int_value: _, unit } => {
            let unit = match unit.as_ref() {
                "px" => LengthUnit::Px,
                "pt" => LengthUnit::Pt,
                "em" => LengthUnit::Em,
                "rem" => LengthUnit::Rem,
                "%" => LengthUnit::Percent,
                "vh" => LengthUnit::Vh,
                "vw" => LengthUnit::Vw,
                _ => LengthUnit::Px,
            };
            Some(CSSValue::Length(*value as f32, unit))
        }
        Token::Percentage { has_sign: _, unit_value, int_value: _ } => {
            Some(CSSValue::Percentage(*unit_value as f32))
        }
        Token::Number { has_sign: _, value, int_value: _ } => {
            Some(CSSValue::Number(*value as f32))
        }
        Token::Ident(ident) => {
            Some(CSSValue::Keyword(ident.to_string()))
        }
        Token::QuotedString(s) => {
            Some(CSSValue::String(s.to_string()))
        }
        Token::Hash(hash) | Token::IDHash(hash) => {
            // Parse hex color
            if let Some(color) = parse_hex_color(&hash.to_string()) {
                Some(CSSValue::Color(color))
            } else {
                None
            }
        }
        Token::Function(name) => {
            match name.as_ref() {
                "rgb" | "rgba" => {
                    parser.parse_nested_block(|parser| {
                        parse_rgb_color(parser)
                    }).ok()
                }
                _ => None
            }
        }
        _ => None,
    }
}

fn parse_hex_color(hex: &str) -> Option<Color> {
    let hex = hex.trim_start_matches('#');
    
    match hex.len() {
        3 => {
            // Short form: #RGB
            let r = u8::from_str_radix(&hex[0..1], 16).ok()? as f32 / 15.0;
            let g = u8::from_str_radix(&hex[1..2], 16).ok()? as f32 / 15.0;
            let b = u8::from_str_radix(&hex[2..3], 16).ok()? as f32 / 15.0;
            Some(Color { r, g, b, a: 1.0 })
        }
        6 => {
            // Long form: #RRGGBB
            let r = u8::from_str_radix(&hex[0..2], 16).ok()? as f32 / 255.0;
            let g = u8::from_str_radix(&hex[2..4], 16).ok()? as f32 / 255.0;
            let b = u8::from_str_radix(&hex[4..6], 16).ok()? as f32 / 255.0;
            Some(Color { r, g, b, a: 1.0 })
        }
        _ => None
    }
}

fn parse_rgb_color(parser: &mut Parser) -> Result<CSSValue, ParseError> {
    parser.skip_whitespace();
    
    let r = match parser.next()? {
        Token::Number { value, .. } => (*value as f32 / 255.0).clamp(0.0, 1.0),
        _ => return Err(ParseError::InvalidValue),
    };
    
    parser.expect_comma()?;
    
    let g = match parser.next()? {
        Token::Number { value, .. } => (*value as f32 / 255.0).clamp(0.0, 1.0),
        _ => return Err(ParseError::InvalidValue),
    };
    
    parser.expect_comma()?;
    
    let b = match parser.next()? {
        Token::Number { value, .. } => (*value as f32 / 255.0).clamp(0.0, 1.0),
        _ => return Err(ParseError::InvalidValue),
    };
    
    // Optional alpha
    let a = if parser.try_parse(|p| p.expect_comma()).is_ok() {
        match parser.next()? {
            Token::Number { value, .. } => *value as f32,
            _ => 1.0,
        }
    } else {
        1.0
    };
    
    Ok(CSSValue::Color(Color { r, g, b, a }))
}

fn combine_values(property: &str, values: Vec<CSSValue>) -> CSSValue {
    match property {
        "font-family" => {
            let families: Vec<String> = values.into_iter()
                .filter_map(|v| match v {
                    CSSValue::String(s) | CSSValue::Keyword(s) => Some(s),
                    _ => None,
                })
                .collect();
            CSSValue::FontFamily(families)
        }
        _ => values.into_iter().next().unwrap_or(CSSValue::Keyword("inherit".to_string()))
    }
}

#[derive(Debug, Clone)]
pub enum ParseError {
    InvalidSelector,
    InvalidValue,
    UnexpectedToken,
}

impl From<cssparser::ParseError<'_, ()>> for ParseError {
    fn from(_: cssparser::ParseError<'_, ()>) -> Self {
        ParseError::UnexpectedToken
    }
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            ParseError::InvalidSelector => write!(f, "Invalid CSS selector"),
            ParseError::InvalidValue => write!(f, "Invalid CSS value"),
            ParseError::UnexpectedToken => write!(f, "Unexpected token in CSS"),
        }
    }
}

impl std::error::Error for ParseError {}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_parse_simple_css() {
        let css = r#"
            body {
                font-family: "Helvetica", sans-serif;
                font-size: 14px;
                color: #333;
                background-color: rgb(255, 255, 255);
            }
            
            h1, h2 {
                color: #000;
                font-weight: bold;
            }
        "#;
        
        let stylesheet = parse_css(css).unwrap();
        assert_eq!(stylesheet.rules.len(), 2);
        
        let body_rule = &stylesheet.rules[0];
        assert_eq!(body_rule.declarations.len(), 4);
    }
}