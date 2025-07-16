// Main Browser module for NeXTSTEP Browser
// Integrates all components into a working web browser

use std::sync::{Arc, Mutex};
use std::collections::VecDeque;

use crate::html_parser::{HTMLParser, HTMLDocument};
use crate::css_parser::ComputedStyle;
use crate::postscript_renderer::PostScriptRenderer;
use crate::network::HTTPClient;
use crate::layout::{LayoutEngine, LayoutBox};

pub struct NeXTWebBrowser {
    // Core components
    http_client: HTTPClient,
    html_parser: HTMLParser,
    layout_engine: LayoutEngine,
    ps_renderer: PostScriptRenderer,
    
    // Browser state
    current_document: Option<HTMLDocument>,
    current_url: String,
    history: BrowserHistory,
    bookmarks: Vec<Bookmark>,
    
    // UI state
    window: BrowserWindow,
    address_bar_text: String,
    address_bar_focused: bool,
    loading: bool,
    
    // NeXTSTEP integration
    workspace: Arc<WorkspaceManager>,
}

struct BrowserHistory {
    back_stack: VecDeque<String>,
    forward_stack: VecDeque<String>,
}

struct Bookmark {
    title: String,
    url: String,
}

struct BrowserWindow {
    width: f32,
    height: f32,
    toolbar_height: f32,
}

impl NeXTWebBrowser {
    pub fn new(workspace: Arc<WorkspaceManager>) -> Result<Self, Box<dyn std::error::Error>> {
        let http_client = HTTPClient::new()?;
        let html_parser = HTMLParser::new(http_client.clone());
        
        Ok(NeXTWebBrowser {
            http_client,
            html_parser,
            layout_engine: LayoutEngine::new(800.0, 600.0),
            ps_renderer: PostScriptRenderer::new(),
            current_document: None,
            current_url: String::new(),
            history: BrowserHistory::new(),
            bookmarks: Vec::new(),
            window: BrowserWindow {
                width: 800.0,
                height: 600.0,
                toolbar_height: 80.0,
            },
            address_bar_text: String::new(),
            address_bar_focused: false,
            loading: false,
            workspace,
        })
    }
    
    pub fn navigate_to(&mut self, url: &str) -> Result<(), Box<dyn std::error::Error>> {
        println!("Navigating to: {}", url);
        
        // Update history
        if !self.current_url.is_empty() {
            self.history.push_back(self.current_url.clone());
        }
        self.history.clear_forward();
        
        // Set loading state
        self.loading = true;
        self.current_url = url.to_string();
        self.address_bar_text = url.to_string();
        
        // Fetch the page
        let response = self.http_client.get(url)?;
        
        // Check status
        if response.status_code >= 400 {
            return Err(format!("HTTP Error: {}", response.status_code).into());
        }
        
        // Parse HTML
        let document = self.html_parser.parse(&response.body, url.to_string())?;
        
        // Update layout engine viewport
        let content_height = self.window.height - self.window.toolbar_height;
        self.layout_engine = LayoutEngine::new(self.window.width, content_height);
        
        // Compute layout
        let layout_tree = self.layout_engine.compute_layout(&document.root);
        
        // Render to PostScript
        let ps_output = self.ps_renderer.render(&layout_tree);
        
        // Display the rendered content
        self.display_content(&ps_output)?;
        
        // Update state
        self.current_document = Some(document);
        self.loading = false;
        
        println!("Navigation complete");
        Ok(())
    }
    
    pub fn reload(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        if !self.current_url.is_empty() {
            let url = self.current_url.clone();
            self.navigate_to(&url)
        } else {
            Ok(())
        }
    }
    
    pub fn go_back(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        if let Some(url) = self.history.go_back(&self.current_url) {
            self.navigate_to(&url)
        } else {
            Ok(())
        }
    }
    
    pub fn go_forward(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        if let Some(url) = self.history.go_forward(&self.current_url) {
            self.navigate_to(&url)
        } else {
            Ok(())
        }
    }
    
    pub fn show(&mut self) {
        println!("Showing browser window");
        // In real implementation, would show NeXTSTEP window
    }
    
    pub fn handle_click(&mut self, point: Point, button: MouseButton) -> Option<BrowserAction> {
        // Check if click is in toolbar
        if point.y < self.window.toolbar_height {
            return self.handle_toolbar_click(point);
        }
        
        // Check if click is on a link
        if let Some(url) = self.find_link_at_point(point) {
            return Some(BrowserAction::Navigate(url));
        }
        
        None
    }
    
    fn handle_toolbar_click(&mut self, point: Point) -> Option<BrowserAction> {
        // Simplified toolbar hit testing
        if point.x < 60.0 && point.y > 50.0 && point.y < 75.0 {
            return Some(BrowserAction::Back);
        }
        if point.x > 70.0 && point.x < 130.0 && point.y > 50.0 && point.y < 75.0 {
            return Some(BrowserAction::Forward);
        }
        
        // Address bar
        if point.y > 10.0 && point.y < 40.0 {
            self.focus_address_bar();
        }
        
        None
    }
    
    fn find_link_at_point(&self, _point: Point) -> Option<String> {
        // TODO: Implement link hit testing
        None
    }
    
    pub fn focus_address_bar(&mut self) {
        self.address_bar_focused = true;
    }
    
    pub fn address_bar_focused(&self) -> bool {
        self.address_bar_focused
    }
    
    pub fn get_address_bar_text(&self) -> Option<String> {
        if self.address_bar_focused && !self.address_bar_text.is_empty() {
            Some(self.address_bar_text.clone())
        } else {
            None
        }
    }
    
    fn display_content(&self, ps_output: &str) -> Result<(), Box<dyn std::error::Error>> {
        // In real implementation, would send PostScript to Display PostScript server
        println!("Rendering {} bytes of PostScript", ps_output.len());
        
        // For debugging, save to file
        if cfg!(debug_assertions) {
            std::fs::write("browser_output.ps", ps_output)?;
            println!("Saved PostScript output to browser_output.ps");
        }
        
        Ok(())
    }
    
    pub fn add_bookmark(&mut self, title: String, url: String) {
        self.bookmarks.push(Bookmark { title, url });
    }
    
    pub fn get_bookmarks(&self) -> &[Bookmark] {
        &self.bookmarks
    }
}

impl BrowserHistory {
    fn new() -> Self {
        BrowserHistory {
            back_stack: VecDeque::new(),
            forward_stack: VecDeque::new(),
        }
    }
    
    fn push_back(&mut self, url: String) {
        self.back_stack.push_back(url);
        
        // Limit history size
        if self.back_stack.len() > 100 {
            self.back_stack.pop_front();
        }
    }
    
    fn clear_forward(&mut self) {
        self.forward_stack.clear();
    }
    
    fn go_back(&mut self, current: &str) -> Option<String> {
        if let Some(url) = self.back_stack.pop_back() {
            self.forward_stack.push_back(current.to_string());
            Some(url)
        } else {
            None
        }
    }
    
    fn go_forward(&mut self, current: &str) -> Option<String> {
        if let Some(url) = self.forward_stack.pop_back() {
            self.back_stack.push_back(current.to_string());
            Some(url)
        } else {
            None
        }
    }
}

// Public types for main.rs
pub enum BrowserAction {
    Navigate(String),
    Back,
    Forward,
    None,
}

// Placeholder types - would be from nextstep-sys
pub struct WorkspaceManager;
impl WorkspaceManager {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        Ok(WorkspaceManager)
    }
    
    pub fn register_service<F>(&self, _name: &str, _handler: F) -> Result<(), Box<dyn std::error::Error>>
    where F: Fn(&str) + 'static {
        Ok(())
    }
    
    pub fn register_drop_types(&self, _types: &[&str]) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

#[derive(Debug, Clone, Copy)]
pub enum MouseButton {
    Left,
    Right,
    Middle,
}

// Event types
pub enum Event {
    MouseDown { point: Point, button: MouseButton },
    KeyDown { key: Key, modifiers: Modifiers },
    WindowClose,
    ServiceRequest { service: String, data: String },
}

#[derive(Debug, Clone, Copy)]
pub enum Key {
    Return,
    Escape,
    L,
    R,
    Q,
}

#[derive(Debug, Clone, Copy)]
pub struct Modifiers {
    pub cmd: bool,
    pub shift: bool,
    pub alt: bool,
    pub ctrl: bool,
}

impl Modifiers {
    pub fn contains(&self, modifier: Modifiers) -> bool {
        (modifier.cmd && self.cmd) ||
        (modifier.shift && self.shift) ||
        (modifier.alt && self.alt) ||
        (modifier.ctrl && self.ctrl)
    }
}

impl Modifiers {
    pub const CMD: Modifiers = Modifiers { cmd: true, shift: false, alt: false, ctrl: false };
}

pub struct EventLoop;
impl EventLoop {
    pub fn new() -> Self {
        EventLoop
    }
    
    pub fn run<F>(self, mut handler: F) where F: FnMut(Event) -> bool {
        // Simulated event loop
        println!("Event loop started");
        
        // In real implementation, would integrate with NeXTSTEP event system
        // For now, just run once
        let _ = handler(Event::MouseDown { 
            point: Point { x: 100.0, y: 200.0 }, 
            button: MouseButton::Left 
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_browser_creation() {
        let workspace = Arc::new(WorkspaceManager::new().unwrap());
        let browser = NeXTWebBrowser::new(workspace);
        assert!(browser.is_ok());
    }
    
    #[test]
    fn test_history() {
        let mut history = BrowserHistory::new();
        history.push_back("http://example.com".to_string());
        history.push_back("http://example.com/page1".to_string());
        
        let back = history.go_back("http://example.com/page2");
        assert_eq!(back, Some("http://example.com/page1".to_string()));
        
        let forward = history.go_forward("http://example.com/page1");
        assert_eq!(forward, Some("http://example.com/page2".to_string()));
    }
}