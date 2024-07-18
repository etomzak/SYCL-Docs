# Copyright (c) 2011-2024 The Khronos Group, Inc.
# SPDX-License-Identifier: Apache-2.0

require 'asciidoctor/extensions' unless RUBY_ENGINE == 'opal'

include ::Asciidoctor

# Make automatic cross references for API names in the HTML render.
#
# This extension assumes that APIs are defined in Asciidoc as listing blocks
# with a particular structure:
#
# * The listing block must define an "id" attribute;
# * The listing block must have a title; and
# * The title must have one occurrence of the "[apidef]" role, where the text
#   in that role is the name of the API.
#
# Here is an example that defines the API "foobar":
#
#   .[apidef]#foobar#
#   [source,id=api:foobar]
#   ----
#   int foobar(void* p)
#   ----
#
# This extension also looks for occurrences of the "[api]" role.  The text in
# this role must exactly match the text in one of the "[apidef]" roles.  This
# extension wraps the text in the "[api]" role with a cross reference link
# to the listing block with the corresponding "[apidef]".  For example, consider
# Asciidoc like this:
#
#   Use the [api]#foobar# function to initialize the system.
#
# This extension wraps the text "foobar" with an HTML anchor that links to the
# listing block whose id is "api::foobar".
#
# Note that an "API" can be anything.  This extension only cares that the text
# in the "[apidef]" role matches the text in the "[api]" role.
#
# Typically, projects using this extension also provide some custom CSS styling
# for the "apidef" and "api" HTML classes.

class AddApiXrefs < Extensions::Postprocessor
  include Asciidoctor::Logging

  ApiSpan = /<span class="api">([\w:]*)<\/span>/
  ApiDefSpan = /<span class="apidef">([\w:]*)<\/span>/
  ApiIdDiv = /<div id="([\w:-]*)"/

  def process document, output

    if document.basebackend? 'html'
      # Scan through all the HTML lines looking for the "[apidef]" definitions.
      # A typical definition looks like this:
      #
      # <div id="ID" class="listingblock">
      # <a href="#ID"></a>
      # <div class="title"><span class="apidef">NAME</span></div>
      #
      # where the <a> element above may or may not be present, depending on
      # whether the listing block also uses the "synopsis" extension.
      #
      api_id_array = output.lines.each_cons(3).filter_map do |prev2, prev1, cur|
        api = cur.scan(ApiDefSpan).first
        api_id = prev1.scan(ApiIdDiv).first || prev2.scan(ApiIdDiv).first
        [api.first, api_id.first] if api && api_id
      end

      # Diagnose duplicate id definitions, and create a hash mapping each API
      # name to its ID.
      api_to_id = {}
      api_id_array.map do |api, api_id|
        if api_to_id.key?(api)
          old_id = api_to_id[api]
          logger.error "[api]##{api}# multiply defined (id=#{old_id} and id=#{api_id})"
        else
          api_to_id[api] = api_id
        end
      end

      # Do another scan through the HTML, looking for each occurrence of
      #
      #   <span class="api">NAME</span>.
      i = 0
      new_output = ''
      output.to_enum(:scan,ApiSpan).map{Regexp.last_match}.each do |m|
        api = m[1]
        # Make sure there was a definition for this API.  Diagnose an error if
        # not.
        if not api_to_id.key?(api)
          logger.error "[api]##{api}#: Not defined"
        else
          # Wrap <span> in an anchor that links to the definition.
          first, last = m.offset(0)
          new_output << output[i..first-1]
          new_output << '<a href="#' << api_to_id[api] << '">' << m[0] << '</a>'
          i = last
        end
      end
      new_output << output[i..-1]
      output = new_output
    end
    output

  end
end