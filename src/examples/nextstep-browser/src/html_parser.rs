// HTML Parser module for NeXTSTEP Browser
// Handles HTML parsing with NeXTSTEP-specific optimizations

use std::collections::HashMap;
use html5ever::parse_document;
use html5ever::tendril::TendrilSink;
use html5ever::tree_builder::TreeBuilderOpts;
use html5ever::ParseOpts;
use markup5ever_rcdom::{Handle, NodeData, RcDom};

use crate::css_parser::{StyleSheet, ComputedStyle};
use crate::network::HTTPClient;

#[derive(Debug, Clone)]
pub struct HTMLDocument {
    pub root: HTMLElement,
    pub base_url: String,
    pub title: String,
    pub stylesheets: Vec<StyleSheet>,
}

#[derive(Debug, Clone)]
pub struct HTMLElement {
    pub tag: String,
    pub attributes: HashMap<String, String>,
    pub children: Vec<HTMLNode>,
    pub computed_style: ComputedStyle,
}

#[derive(Debug, Clone)]
pub enum HTMLNode {
    Element(HTMLElement),
    Text(String),
    Comment(String),
}

pub struct HTMLParser {
    base_url: String,
    http_client: HTTPClient,
}

impl HTMLParser {
    pub fn new(http_client: HTTPClient) -> Self {
        HTMLParser {
            base_url: String::new(),
            http_client,
        }
    }
    
    pub fn parse(&mut self, html: &str, base_url: String) -> Result<HTMLDocument, ParseError> {
        self.base_url = base_url.clone();
        
        // Parse HTML using html5ever
        let opts = ParseOpts {
            tree_builder: TreeBuilderOpts {
                drop_doctype: true,
                ..Default::default()
            },
            ..Default::default()
        };
        
        let dom = parse_document(RcDom::default(), opts)
            .from_utf8()
            .read_from(&mut html.as_bytes())?;
        
        // Convert RcDom to our HTMLElement structure
        let root = self.convert_node(&dom.document)?;
        
        // Extract title
        let title = self.extract_title(&root);
        
        // Find and load stylesheets
        let stylesheets = self.load_stylesheets(&root)?;
        
        Ok(HTMLDocument {
            root,
            base_url,
            title,
            stylesheets,
        })
    }
    
    fn convert_node(&self, handle: &Handle) -> Result<HTMLElement, ParseError> {
        let node = handle;
        
        match node.data {
            NodeData::Document => {
                // Find the html element
                for child in node.children.borrow().iter() {
                    if let NodeData::Element { ref name, .. } = child.data {
                        if &name.local == "html" {
                            return self.convert_node(child);
                        }
                    }
                }
                Err(ParseError::InvalidHTML("No html element found".to_string()))
            }
            
            NodeData::Element { ref name, ref attrs, .. } => {
                let mut element = HTMLElement {
                    tag: name.local.to_string(),
                    attributes: HashMap::new(),
                    children: Vec::new(),
                    computed_style: ComputedStyle::default(),
                };
                
                // Convert attributes
                for attr in attrs.borrow().iter() {
                    element.attributes.insert(
                        attr.name.local.to_string(),
                        attr.value.to_string(),
                    );
                }
                
                // Convert children
                for child in node.children.borrow().iter() {
                    match child.data {
                        NodeData::Element { .. } => {
                            let child_element = self.convert_node(child)?;
                            element.children.push(HTMLNode::Element(child_element));
                        }
                        NodeData::Text { ref contents } => {
                            let text = contents.borrow().to_string();
                            if !text.trim().is_empty() {
                                element.children.push(HTMLNode::Text(text));
                            }
                        }
                        NodeData::Comment { ref contents } => {
                            element.children.push(HTMLNode::Comment(contents.to_string()));
                        }
                        _ => {} // Skip other node types
                    }
                }
                
                Ok(element)
            }
            
            _ => Err(ParseError::InvalidHTML("Unexpected node type".to_string()))
        }
    }
    
    fn extract_title(&self, root: &HTMLElement) -> String {
        if let Some(head) = self.find_child_by_tag(root, "head") {
            if let Some(title) = self.find_child_by_tag(head, "title") {
                return self.get_text_content(title);
            }
        }
        "Untitled".to_string()
    }
    
    fn find_child_by_tag<'a>(&self, element: &'a HTMLElement, tag: &str) -> Option<&'a HTMLElement> {
        for child in &element.children {
            if let HTMLNode::Element(child_element) = child {
                if child_element.tag == tag {
                    return Some(child_element);
                }
                // Recursive search
                if let Some(found) = self.find_child_by_tag(child_element, tag) {
                    return Some(found);
                }
            }
        }
        None
    }
    
    fn get_text_content(&self, element: &HTMLElement) -> String {
        let mut text = String::new();
        
        for child in &element.children {
            match child {
                HTMLNode::Text(t) => text.push_str(t),
                HTMLNode::Element(e) => text.push_str(&self.get_text_content(e)),
                HTMLNode::Comment(_) => {}
            }
        }
        
        text.trim().to_string()
    }
    
    fn load_stylesheets(&mut self, root: &HTMLElement) -> Result<Vec<StyleSheet>, ParseError> {
        let mut stylesheets = Vec::new();
        let mut urls = Vec::new();
        
        // Find all link elements with rel="stylesheet"
        self.find_stylesheet_links(root, &mut urls);
        
        // Load each stylesheet
        for url in urls {
            match self.http_client.get(&url) {
                Ok(response) => {
                    if let Ok(stylesheet) = crate::css_parser::parse_css(&response.body) {
                        stylesheets.push(stylesheet);
                    }
                }
                Err(e) => {
                    eprintln!("Failed to load stylesheet {}: {:?}", url, e);
                }
            }
        }
        
        // Also parse inline styles
        self.find_inline_styles(root, &mut stylesheets);
        
        Ok(stylesheets)
    }
    
    fn find_stylesheet_links(&self, element: &HTMLElement, urls: &mut Vec<String>) {
        if element.tag == "link" {
            if let (Some(rel), Some(href)) = (
                element.attributes.get("rel"),
                element.attributes.get("href")
            ) {
                if rel == "stylesheet" {
                    let full_url = self.resolve_url(href);
                    urls.push(full_url);
                }
            }
        }
        
        for child in &element.children {
            if let HTMLNode::Element(child_element) = child {
                self.find_stylesheet_links(child_element, urls);
            }
        }
    }
    
    fn find_inline_styles(&self, element: &HTMLElement, stylesheets: &mut Vec<StyleSheet>) {
        if element.tag == "style" {
            let css_text = self.get_text_content(element);
            if let Ok(stylesheet) = crate::css_parser::parse_css(&css_text) {
                stylesheets.push(stylesheet);
            }
        }
        
        for child in &element.children {
            if let HTMLNode::Element(child_element) = child {
                self.find_inline_styles(child_element, stylesheets);
            }
        }
    }
    
    fn resolve_url(&self, href: &str) -> String {
        if href.starts_with("http://") || href.starts_with("https://") {
            href.to_string()
        } else if href.starts_with("//") {
            format!("https:{}", href)
        } else if href.starts_with("/") {
            if let Ok(base) = url::Url::parse(&self.base_url) {
                format!("{}://{}{}", base.scheme(), base.host_str().unwrap_or(""), href)
            } else {
                href.to_string()
            }
        } else {
            format!("{}/{}", self.base_url.trim_end_matches('/'), href)
        }
    }
}

#[derive(Debug, Clone)]
pub enum ParseError {
    InvalidHTML(String),
    NetworkError(String),
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            ParseError::InvalidHTML(msg) => write!(f, "Invalid HTML: {}", msg),
            ParseError::NetworkError(msg) => write!(f, "Network error: {}", msg),
        }
    }
}

impl std::error::Error for ParseError {}

impl From<std::io::Error> for ParseError {
    fn from(e: std::io::Error) -> Self {
        ParseError::InvalidHTML(format!("IO error: {}", e))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_parse_simple_html() {
        let html = r#"
            <!DOCTYPE html>
            <html>
                <head>
                    <title>Test Page</title>
                </head>
                <body>
                    <h1>Hello World</h1>
                    <p>This is a test.</p>
                </body>
            </html>
        "#;
        
        let client = HTTPClient::new().unwrap();
        let mut parser = HTMLParser::new(client);
        let doc = parser.parse(html, "http://example.com".to_string()).unwrap();
        
        assert_eq!(doc.title, "Test Page");
        assert_eq!(doc.root.tag, "html");
    }
}