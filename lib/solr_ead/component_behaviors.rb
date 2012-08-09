require "sanitize"

module SolrEad::ComponentBehaviors

  # Takes a file as its input and returns a Nokogiri::XML::NodeSet of component <c> nodes
  #
  # It'll make an attempt at substituting numbered component levels for non-numbered
  # ones.
  def components(file)
    raw = File.read(file).gsub!(/xmlns=".*"/, '')
    raw.gsub!(/c[0-9]{2,2}/,"c")
    xml = Nokogiri::XML(raw)
    return xml.xpath("//c")
  end

  # Used in conjunction with #components, this takes a single Nokogiri::XML::Element
  # representing an <c> node from an ead document, and returns a Nokogiri::XML::Document
  # with any child <c> nodes removed.
  # == Example
  # If I input this Nokogiri::XML::Element
  #   <c>
  #     <did>etc</did>
  #     <scopecontent>etc</scopecontent>
  #     <c>etc</c>
  #     <c>etc</c>
  #   </c>
  # Then I should get back the following Nokogiri::XML::Document
  #   <c>
  #     <did>etc</did>
  #     <scopecontent>etc</scopecontent>
  #   </c>
  def prep(node)
    part = Nokogiri::XML(node.to_s)
    part.xpath("/*/c").each { |e| e.remove }
    return part
  end

  # Because the solr documents created from individual components have been removed from
  # the hierarchy of their original ead, we need to be able to reconstruct the order
  # in which they appeared, as well as their location within the hierarchy.
  #
  # This method takes a single Nokogiri::XMl::Node as its argument that represents a
  # single <c> component node, but with all of this parent nodes still attached. From
  # there we can determine all of its parent <c> nodes so that we can correctly
  # reconstruct its placement within the original ead hierarchy.
  #
  # The solr fields return by this method are:
  #
  # id:: Unique identifier using the id attribute and the <eadid>
  # eadid_s:: The <eadid> node of the ead. This is so we know which ead this component belongs to.
  # parent_id_s:: The id attribute of the parent <c> node
  # parent_id_list_t:: see parent_id_list
  # parent_unittitle_list_t:: see parent_id_list
  # component_children_b:: Boolean field indicating whether or not the component has any child <c> nodes attached to it
  # heading_display:: Custom display heading for component documents
  #
  # These fields are used so that we may reconstruct placement of a single component
  # within the hierarchy of the original ead.
  def additional_component_fields(node, addl_fields = Hash.new)
    addl_fields["id"]                      = [node.xpath("//eadid").text, node.attr("id")].join(":")
    addl_fields["eadid_s"]                 = node.xpath("//eadid").text
    addl_fields["parent_id_s"]             = node.parent.attr("id") unless node.parent.attr("id").nil?
    addl_fields["parent_id_list_t"]        = parent_id_list(node)
    addl_fields["parent_unittitle_list_t"] = parent_unittitle_list(node)
    addl_fields["component_children_b"]    = component_children?(node)
    return addl_fields
  end

  # Array of all id attributes from the component's parent <c> nodes, sorted in descending order
  # This is used to reconstruct the order of component documents that should appear above
  # a specific item-level component.
  def parent_id_list(node, results = Array.new)
    while node.parent.name == "c"
      parent = node.parent
      results << parent.attr("id") unless parent.attr("id").nil?
      node = parent
    end
    return results.reverse
  end

  # Array of all unittitle nodes from the component's parent <c> nodes, sort in descending order
  # This is useful if you want to display a list of a component's parent containers in
  # the correct order, ex:
  #   ["Series I", "Subseries a", "Sub-subseries 1"]
  # From there, you can assemble and display as you like.
  def parent_unittitle_list(node, results = Array.new)
    while node.parent.name == "c"
      parent = node.parent
      part = Nokogiri::XML(parent.to_xml)
      results << get_title(part)
      node = parent
    end
    return results.reverse
  end

  def get_title(xml)
    title = xml.at("/c/did/unittitle")
    date  = xml.at("/c/did/unitdate")
    if !title.nil? and !title.content.empty?
      return ead_clean_xml(title.content)
    elsif !date.nil? and !date.content.empty?
      return ead_clean_xml(date.content)
    else
      return "[No title available]"
    end
  end

  # Converts formatting elements in the ead into html tags
  def ead_clean_xml(string)
    string.gsub!(/<title/,"<span")
    string.gsub!(/<\/title/,"</span")
    string.gsub!(/render=/,"class=")
    sanitize = Sanitize.clean(string, :elements => ['span'], :attributes => {'span' => ['class']})
    sanitize.gsub("\n",'').gsub(/\s+/, ' ').strip
  end

  # Returns true or false for a component with attached <c> child nodes.
  # A <c> node with a level attribute of either file or item will have no component
  # children attached to it.
  def component_children?(node)
    node.attr("level").match(/file|item/) ? FALSE : TRUE
  end

  # One final method for tweaking our solr fields
  def custom_component_fields(solr_doc)
    solr_doc.merge!({"heading_display" => [ solr_doc["parent_unittitle_list_t"], solr_doc["title_display"] ].join(" >> ") })
  end

end