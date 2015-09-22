set :root, File.dirname(__FILE__)

class ArchivesspaceChecker < Sinatra::Base
  set :assets_precompile, %w(application.js application.css *.png *.jpg)
  set :assets_css_compressor, :scss
  set :assets_js_compressor, :uglifier

  register Sinatra::AssetPipeline
  register Sinatra::Partial

  set :haml, :format => :html5

  PHASE_OPTS = [
    {name: "Manual", value: "'manual'", checked: "checked"},
    {name: "Automatic", value: "'automated'"},
    {name: "Everything", value: "'#ALL'"}
  ]

  OUTPUT_OPTS = {
    'xml' => {name: 'xml', value: 'xml', mime: 'application/xml', :checked => "checked"},
    'csv' => {name: 'csv', value: 'csv', mime: 'text/csv'}
  }

  Saxon::Processor.default.config[:line_numbering] = true

  CHECKER = Schematronium.new(IO.read('schematron/descgrp.sch'))

  stron_xml = Nokogiri::XML(IO.read('schematron/descgrp.sch')).remove_namespaces!
  STRON_REP = stron_xml.xpath('//rule').reduce({}) do |result, rule|
    result[rule.xpath('comment()').text.strip]  = rule.xpath('//assert').map(&:text).map(&:strip)
    result
  end

  def check_file(f, phase)
    # If phase is other than default, bespoke checker
    checker = (phase == "'#ALL'") ? CHECKER : Schematronium.new(IO.read('schematron/descgrp.sch'), phase)
    s_xml = Saxon.XML(f)
    xml = checker.check(s_xml.to_s)
    xml.remove_namespaces!
    xml = xml.xpath("//failed-assert") + xml.xpath("//successful-report")
    xml.each do |el|
      el["line-number"] = s_xml.xpath(el.attr("location")).get_line_number
    end
    xml
  end

  def xml_output(xml, orig_name)
    output = Nokogiri::XML::DocumentFragment.new(Nokogiri::XML::Document.new)
    file = output.add_child("<file file_name='#{orig_name}' total_errors='#{xml.count}'/>").first
    counts = xml.group_by {|el| el.children.map(&:text).join.strip.gsub(/\s+/, ' ')}.map {|k,v| [k,v.count]}.to_h
    err_count = file.add_child("<error_counts />").first
    counts.each do |k,v|
      err_count.add_child("<message count='#{v}'>#{k}</message>")
    end
    errs = file.add_child("<errors />").first
    errs.children = xml

    output
  end

  def csv_output(xml, orig_name)
    CSV.generate(encoding: 'utf-8') do |csv|
      csv << %w|filename total_errors|
      csv << [orig_name, xml.count]
      csv << []
      csv << %w|type location line-number message|
      xml.each do |el|
        csv << [el.name, el['location'], el['line-number'], el.xpath('//text').first.content]
      end
    end
  end

  def output(fmt, xml, orig_name)
    case fmt
    when 'xml'
      xml_output(xml, orig_name)
    when 'csv'
      csv_output(xml, orig_name)
    end
  end

  # Routes
  get "/" do
    haml :index
  end

  post "/result.:filetype" do
    headers "Content-Type" => "#{OUTPUT_OPTS[params[:filetype]][:mime]}; charset=utf8"
    up = params['eadFile']
    output(params[:filetype], check_file(up[:tempfile], params[:phase]), up[:filename]).to_s
  end

  get "/possible-errors" do
    haml :possible_errors
  end
end
