require 'base64'

class EditController < ApplicationController
  STATUS_NEW = 1
  STATUS_SHOW = 2
  STATUS_EDIT = 4
  
  def past
    user_info = user_info_from_session
    @mail = user_info[:mail]
    @client_code = user_info[:client_code]

    @past_contents = extract_contents(user_info, "PAST_INCIDENT")

    @items = user_info[:disp][@past_contents[:code].to_sym]
    @categories = user_info[:categories][@past_contents[:code].to_sym]
    @ports = user_info[:ports][@past_contents[:code].to_sym]

    if user_info[:contents].size > 1
      @news_contents = extract_contents(user_info, "INCIDENT_NEWS")
    end

    @histories = fetch_histories( @past_contents[:code])
    contents_no = @params[:contents_no]
    @values = {} 
    @values = fetch_history_detail(
                      @past_contents[:code], 
                      contents_no) unless contents_no.nil? || contents_no.empty?  


    @values[:contents_code] =  @past_contents[:code]
    @values[:contents_no] = "" 
    gui_status = @params[:status]
    status = ""

    if empty?(gui_status)
      status = STATUS_SHOW unless empty?(contents_no)
    else
      status = STATUS_EDIT unless empty?(contents_no)  
      status = STATUS_NEW if  empty?(contents_no) && !empty?(@params[:category]) 
    end
    @values[:status] = status
    
    if status == STATUS_NEW
      files = JSON.parse(@session["files"])
      new_proc(@past_contents, @values, contents_no, files[0])
      if @error_message
        @value = @params.dup
      end
      @session["files"] =  nil
    end

    if status == STATUS_EDIT
      files = JSON.parse(@session["files"])
      edit_proc(@past_contents, @values, contents_no, files[0])
      if @error_message
        @value = @params.dup
      end
      @session["files"] =  nil
    end
    
    if status == STATUS_SHOW
      pdf_file =  DoscaAPI.pdf_download(@client_code, 
                              @mail, @past_contents[:code], contents_no) 

      @values[:pdf_file] = Settings._settings[:server][:contents_pdf_uri] + "/" + pdf_file
      @values[:contents_code] = @past_contents[:code]
      @values[:contents_no] = contents_no  
      if @values[:termination_date].nil? ||  @values[:termination_date].empty?
        @values[:period]  = nil 
      else 
        @values[:period]  = "period"
      end
    end
  end

  def news
    user_info = user_info_from_session
    @mail = user_info[:mail]
    @client_code = user_info[:client_code]

    @news_contents = extract_contents(user_info, "INCIDENT_NEWS")
    if user_info[:contents].size > 1
      @past_contents = extract_contents(user_info, "PAST_INCIDENT")
    end

    @items = user_info[:disp][@news_contents[:code].to_sym]
    @categories = user_info[:categories][@news_contents[:code].to_sym]
    @ports = user_info[:ports][@news_contents[:code].to_sym]

    @histories = fetch_histories(@news_contents[:code])
    contents_no = @params[:contents_no]
    @values = {} 
    @values = fetch_history_detail(
                      @news_contents[:code], 
                      contents_no) unless contents_no.nil? || contents_no.empty?  

    @values[:contents_code] =  @news_contents[:code]
    @values[:contents_no] = "" 
    gui_status = @params[:status]
    status = ""

    if empty?(gui_status)
      status = STATUS_SHOW unless empty?(contents_no)
    else
      status = STATUS_EDIT unless empty?(contents_no)  
      status = STATUS_NEW if  empty?(contents_no) && !empty?(@params[:category]) 
    end
    @values[:status] = status

    if status == STATUS_NEW
      new_proc(@news_contents, @values, contents_no, nil)
      if @error_message
        @value = @params.dup
      end
      @session["files"] =  nil
    end

    if status == STATUS_EDIT
      edit_proc(@news_contents, @values, contents_no, nil)
      if @error_message
        @value = @params.dup
      end
      @session["files"] =  nil
    end

    if status == STATUS_SHOW
      pdf_file =  DoscaAPI.pdf_download(@client_code, 
                              @mail, @news_contents[:code], contents_no) 

      @values[:pdf_file] = Settings._settings[:server][:contents_pdf_uri] + "/" + pdf_file
      @values[:contents_code] = @news_contents[:code]
      @values[:contents_no] = contents_no  
      if @values[:termination_date].nil? ||  @values[:termination_date].empty?
        @values[:period]  = nil 
      else 
        @values[:period]  = "period"
      end
    end
  end

  def delete 
    @no_render = true
    user_info = user_info_from_session
    @mail = user_info[:mail]
    @client_code = user_info[:client_code]

    resp = DoscaAPI.remove(@client_code, @mail, 
              @params[:contents_code], @params[:contents_no])
    @cgi.out("type" => "application/json") {
      resp.to_json
    }
  rescue => e
    api_response("ERROR", e.to_s)
  end

  def preview
    @no_render = true
    user_info = user_info_from_session
    @mail = user_info[:mail]
    @client_code = user_info[:client_code]

    news_contents = extract_contents(user_info, "INCIDENT_NEWS")
    pdf_file = create_pdf(@params[:contents_code], @params[:contents_no], 
                        news_contents[:name], utc_time, @params)

    open(pdf_file) do |fp|
      basename = File.basename(pdf_file)
      header = {
        "type" => "application/pdf",
        "length" => fp.stat.size,
        "Content-Disposition"=>"download;filename=\"#{basename}\""}
      @cgi.out(header) do
        fp.read
      end
    end

    @session["files"] = nil
  rescue => e
    api_response("ERROR", e.to_s)
  end

  def upload
    @no_render = true
    file_names  = []
    files = @cgi.params["files[]"]
    if !files.is_a?(Array)
      file_names.push(save_temp_file(files))
    else
      files.each do |file|
        file_names.push(save_temp_file(file))
      end
    end
    @session["files"] = file_names.to_json
     
    api_response("SUCCESS", "")
  rescue Exception => e
    api_response("ERROR", e.to_s)
  end

  private

  def new_proc(contents, values, contents_no, pdf_file)
    if !pdf_file
      pdf_file = create_pdf(contents[:code], 
        contents_no, contents[:name], utc_time, @params)
    end

    resp = DoscaAPI.new(@client_code,
                      @mail, contents[:code],  pdf_file, @params) 

    if !has_error?(resp)
      @error_message = resp[:message]
    end
    #File.delete pdf_file if File.exist?(pdf_file)
  end

  def edit_proc(contents, values, contents_no, pdf_file)
    if !dirty?(values, @params)
      @error_message = "no change"
      return
    end

    if !pdf_file
      pdf_file = create_pdf(contents[:code], 
        contents_no, contents[:name], utc_time, @params)
    end

    resp = DoscaAPI.update(@client_code,
                        user_info[:mail], contents[:code], contents_no, pdf_file, @params) 
    if !has_error?(resp)
      @error_message = resp[:message]
    end
    File.delete pdf_file if File.exist?(pdf_file)
  end

  def extract_contents(user_info, keyword)
    user_info[:contents].select{|h| h[:code].index(keyword)}.first
  end

  def user_info_from_session
    username = @session["username"]
    user_info_json = @session[username]
    Application.symbolize_keys(JSON.parse(user_info_json))
  end

  def fetch_histories(contents_code)
    resp = DoscaAPI.history_list(@client_code, @mail, contents_code)
    his = []
    if !has_error?(resp)
      his = resp[:histories]
    end
    
    #sort by no
    his.sort_by{|item| item[:no]} if his.size > 1
  end

  def fetch_history_detail(contents_code, contents_no)
    resp = DoscaAPI.history_detail(@client_code, @mail, contents_code, contents_no) 
    if has_error?(resp)
      {}
    else
      resp
    end
  end

  def dirty?(before, after)
    return true if before.empty?
    before.each {|key, value|
      return true if value != after[key]
    }
    return false
  end
 
  def create_pdf(contents_code, contents_no, title, issue_date, data)
    path = Settings._settings[:server][:temp_directory]
    pdf_name = path + "/" + [@client_code, contents_code, contents_no].join("_") + ".pdf"
    if contents_no.nil? || contents_no.empty?
      pdf_name = path + "/" + [@client_code, contents_code, "new"].join("_") + ".pdf"
    end
    map_picture = save_base64_picture(@cgi.params["map_picture"].to_s, path)
    news_pictures = []
    news_pictures = JSON.parse(@session["files"]) unless @session["files"].nil? || @session["files"].empty?

    pdf = PDFCreator.new(pdf_name, 
          title,
          issue_date, 
          data[:position],  data[:category],
          data[:subject],
          data[:summary],
          map_picture, news_pictures)
    pdf.create()

    pdf_name
  end

  def save_base64_picture(data_url, path)
    png  = Base64.decode64(data_url['data:image/png;base64,'.length..-1])
    file_name = path + '/chart.png'
    File.open(file_name, 'wb') { |f| f.write(png) }
    file_name
  end
  
  def save_temp_file(file) 
    path = [Settings._settings[:server][:temp_directory], file.original_filename].join("/") 
    File.open(path, "w") { |f| f.write file.read }
    path
  end

  def utc_time
    Time.now.utc.to_s
  end

  def empty?(obj) 
    return true if obj.nil?
    return true if obj.empty?
    return false 
  end

  def api_response(result, message)
    json = {
       "result" => result,
       "message" => message
    }.to_json

    @cgi.out("type" => "application/json")  {
       json
    }
  end
end
