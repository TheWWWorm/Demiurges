class_name ELXml
extends RefCounted
## Small, ordered tree for the originals' campaign and scenario documents.
## No executable XML features or external entity loading are used.
static func parse(bytes: PackedByteArray) -> Dictionary:
	var parser := XMLParser.new()
	# XMLParser 4.7 repeats its last token when only trailing CR/LF remains.
	var end := bytes.size()
	while end > 0 and bytes[end - 1] in [9, 10, 13, 32]: end -= 1
	if parser.open_buffer(bytes.slice(0, end)) != OK: return {"error": "Unreadable XML document."}
	var root := {}
	var stack: Array[Dictionary] = []
	while true:
		var code := parser.read()
		if code == ERR_FILE_EOF: break
		if code != OK: return {"error": "Malformed XML document."}
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node := {"tag": parser.get_node_name(), "attrs": {}, "text": "", "children": []}
				for i in parser.get_attribute_count():
					node.attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
				if stack.is_empty():
					if not root.is_empty(): return {"error": "Multiple XML roots."}
					root = node
				else: stack.back().children.append(node)
				if not parser.is_empty(): stack.append(node)
				if stack.size() > 64: return {"error": "XML nesting is too deep."}
			XMLParser.NODE_ELEMENT_END:
				if stack.is_empty() or stack.back().tag != parser.get_node_name(): return {"error": "Mismatched XML element."}
				stack.pop_back()
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if not stack.is_empty(): stack.back().text += parser.get_node_data()
	if not stack.is_empty() or root.is_empty(): return {"error": "Incomplete XML document."}
	return root

static func children(node: Dictionary, name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child: Dictionary in node.get("children", []):
		if child.tag == name: result.append(child)
	return result

static func child(node: Dictionary, name: String) -> Dictionary:
	for element: Dictionary in node.get("children", []):
		if element.tag == name: return element
	return {}

static func value(node: Dictionary, name: String, fallback := "") -> String:
	return String(child(node, name).get("text", fallback)).strip_edges()
