import Testing

@testable import ArcaCore

/// `{token}` templates, as a heading's `{name} {version}` (design.md "The
/// file").
@Suite("Template")
struct TemplateTests {
  @Test("a template's tokens, once each, in the order they first appear")
  func tokens() {
    #expect(Template("{name} {version} ({name})").tokens == ["name", "version"])
  }

  @Test("each token takes its value")
  func render() {
    let rendering = Template("{name} {version}").render(["name": "menuz", "version": "0.3.0"])
    #expect(rendering == Rendering(text: "menuz 0.3.0", missing: []))
  }

  @Test("a token with no value stays as written and is named once, in the order it first appears")
  func missing() {
    let rendering = Template("{name} {commit} · {commit}").render(["name": "menuz"])
    #expect(rendering == Rendering(text: "menuz {commit} · {commit}", missing: ["commit"]))
    #expect(Template("{b} {a} {b}").render([:]) == Rendering(text: "{b} {a} {b}", missing: ["b", "a"]))
  }

  @Test("an empty value is a value, so its token is not missing")
  func emptyValue() {
    #expect(Template("{name}").render(["name": ""]) == Rendering(text: "", missing: []))
  }

  @Test(
    "a brace that opens no token is text",
    arguments: ["body { color: red }", "a{b:c}", "{}", "{1x}", "{_x}", "{a-b}", "{é}", "{name", "name}", "{ name }"])
  func notTokens(text: String) {
    #expect(Template(text).parts == [.text(text)])
    #expect(Template(text).render(["name": "menuz", "x": "y"]) == Rendering(text: text, missing: []))
  }

  @Test("a token's name is a letter, then letters, digits and underscores")
  func names() {
    #expect(Template("{App_2}{x}").parts == [.token("App_2"), .token("x")])
    #expect(Template("a{b}c").parts == [.text("a"), .token("b"), .text("c")])
  }

  @Test("doubled braces keep one brace each side of the value")
  func doubled() {
    #expect(Template("{{name}}").parts == [.text("{"), .token("name"), .text("}")])
    #expect(Template("{{name}}").render(["name": "menuz"]).text == "{menuz}")
  }

  @Test("a value is not read for tokens")
  func valueNotExpanded() {
    #expect(Template("{a}").render(["a": "{b}", "b": "x"]) == Rendering(text: "{b}", missing: []))
  }

  @Test("the text around tokens keeps every character")
  func unicode() {
    #expect(Template("Über {name} ✓").render(["name": "menuz"]).text == "Über menuz ✓")
  }
}
