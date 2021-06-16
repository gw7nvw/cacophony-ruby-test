require 'net/http/post/multipart'
require 'json'
require 'time'

def api_login(username, pass,server)
  if server=="prod" then 
    @cac_url="https://api.cacophony.org.nz"
  elsif server=='test' then
    @cac_url="https://api-test.cacophony.org.nz"
  else 
    @cac_url=server
  end
  uri=URI.parse(@cac_url+"/authenticate_user")
  http=Net::HTTP.new(uri.host, uri.port)
  if @cac_url[0..4]=='https' then
    http.use_ssl=true
    http.verify_mode=OpenSSL::SSL::VERIFY_NONE
  end
  req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
  params = get_params({nameOrEmail: username, password: pass})
  req.body = params.to_json
  res = http.request(req)
  resf=JSON.parse(res.body)
  resf["token"]
end

def api_reprocessPOST(token,recordings)
  path="/api/v1/reprocess"
  params = get_params({recordings: recordings})
  send_JSON_POST(path, token, params)
end

def api_alerts_get(token,deviceId)
  path="/api/v1/alerts/device/"+deviceId
  params=nil
  send_JSON_GET(path, token, params)
end

def api_alerts_post(token,name,conditions,frequency,deviceId)
  path="/api/v1/alerts/"
  params = get_params({
           name: alertName,
           conditions: conditions,
           deviceId: deviceId,
           frequencySeconds: frequency
        });
  send_JSON_POST(path, token, params)
end

def api_events_get(token,deviceId)
  path="/api/v1/events/"
  params=get_params({deviceId: deviceId})
  send_JSON_GET(path, token, params)
end

def api_groups_get(token,nameorid)
  path="/api/v1/groups/"+nameorid
  params=nil
  send_JSON_GET(path, token, params)
end

def api_groups_post(token,name)
  path="/api/v1/groups/"
  params=get_params({groupname: name})
  send_JSON_POST(path, token, params)
end

def api_group_devices(token, group)
  path="/api/v1/groups/"+group.to_s+"/devices"
  params = nil
  send_JSON_GET(path, token, params)
end

def api_events(token,device)
  path="/api/v1/events"
  params = get_params({deviceId: device})
  send_JSON_GET(path, token, params)
end

def api_v1_recordings_report(token,type,audiobait,wherestr,offset,limit,order,tags,tagmode,filteroptions)
  path="/api/v1/recordings/report"
  params = get_params({ type: type, audiobait: audiobait, where: wherestr, offset: offset, limit: limit, order: order, tags: tags, tagMode: tagmode, filterOptions: filteroptions})
  result=send_JSON_GET(path, token, params)
end

def api_v1_recordings(token,wherestr)
  path="/api/v1/recordings"
  params = get_params({ where: wherestr})
  result=send_JSON_GET(path, token, params)
end

def api_v1_recording_get(token, id)
  path="/api/v1/recordings/"+id.to_s
  params = nil
  result=send_JSON_GET(path, token, params)
end

def api_v1_recording_delete(token, id)
  path="/api/v1/recordings/"+id.to_s
  params = nil
  result=send_JSON_DELETE(path, token, params)
end

def api_recording_track_get(token,id)
  path="/api/v1/recordings/"+id.to_s+"/tracks"
  params = nil
  result=send_JSON_GET(path, token, params)
end

def api_v1_devices(token,deviceName,groupName)
  path="/api/v1/devices/"+deviceName+"/in-group/"+groupName
  params = nil
  result=send_JSON_GET(path, token, params)
end

def api_devices_post(token,deviceName,group)
  path="/api/v1/devices/"
  params=get_params({devicename: deviceName, password: deviceName+"_password", group: group.to_s})
  send_JSON_POST(path, token, params)
end



def api_v1_monitoring_page(token, page_size, page, search_from, search_to, devices, groups)
  path="/api/v1/monitoring/page"
  params=get_params({"page-size": page_size, "page": page, from: search_from, until: search_to, devices: devices, groups: groups})
  puts params
  result=send_JSON_GET(path, token, params)
end

################################## handlers  ###########################################
def api_v1_signedurl(filetoken)
  path="/api/v1/signedUrl?jwt="+filetoken
  params={jwt: filetoken}
  uri=URI.parse(@cac_url+path)
  http=Net::HTTP.new(uri.host, uri.port)
  if uri.to_s[0..4]=="https" then
    http.use_ssl=true
    http.verify_mode=OpenSSL::SSL::VERIFY_NONE
  end
  req = Net::HTTP::Get.new(uri.request_uri)
  req.body = params.to_json
  res = http.request(req)
  res.body
end

def api_v1_recordings_devicePOST(token,id,filepath,type,filehash)
  path="/api/v1/recordings/device/"+id.to_i.to_s
  if type=='audio' then 
    params = '{"type":"audio","duration":60,"recordingDateTime":"'+Time.now.utc.iso8601+'"}'
    puts "DEBUG: "+params
  else
       if filehash then 
             params = '{"type":"'+type+'","fileHash":"'+filehash+'"}'
           else
             params = '{"type":"'+type+'"}'
           end
    puts "DEBUG: "+params

  end
  result=send_JSON_multipart_POST(path, token, params,filepath)
end


def api_v1_recordings_device_groupPOST(token,devicename, groupname,filepath,type,filehash)
  path="/api/v1/recordings/device/"+devicename+"/group/"+groupname
  if type=='audio' then
    params = '{"type":"audio","duration":60,"recordingDateTime":"'+Time.now.utc.iso8601+'"}'
    puts "DEBUG: "+params
  else
       if filehash then
             params = '{"type":"'+type+'","fileHash":"'+filehash+'"}'
           else
             params = '{"type":"'+type+'"}'
           end

  end
  result=send_JSON_multipart_POST(path, token, params,filepath)
end


def api_v1_recordings_reportGET(token,rectype,whereclause)
  path="/api/v1/recordings/report"
  params = get_params({type: rectype, where: whereclause})
  send_JSON_GET(path, token, params)
end


def send_JSON_POST(path,token,params)
  uri=URI.parse(@cac_url+path)
  http=Net::HTTP.new(uri.host, uri.port)
  if uri.to_s[0..4]=="https" then
    http.use_ssl=true
    http.verify_mode=OpenSSL::SSL::VERIFY_NONE
  end
  req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json', 'Authorization' => token)
  req.body = params.to_json
  res = http.request(req)
  res.body
end


def send_JSON_multipart_POST(path,token,params,filepath)
  `curl -H "Authorization: #{token}" -F 'data=#{params}' -F file=@'#{filepath}' #{@cac_url}#{path}`
end


def send_JSON_GET(path,token,params)
  uri=URI.parse(@cac_url+path)
  http=Net::HTTP.new(uri.host, uri.port)
  if uri.to_s[0..4]=="https" then
    http.use_ssl=true
    http.verify_mode=OpenSSL::SSL::VERIFY_NONE
  end
  if params then 
    req = Net::HTTP::Get.new("#{uri.path}?".concat(params.collect { |k,v| "#{k}=#{CGI::escape(v.to_s)}" }.join('&')), 'Content-Type' => 'application/json', 'authorization' => token)
  else 
    req=Net::HTTP::Get.new(uri.path, 'Content-Type' => 'application/json', 'authorization' => token)
  end
  res = http.request(req)
  res.body
end

def send_JSON_DELETE(path,token,params)
  uri=URI.parse(@cac_url+path)
  http=Net::HTTP.new(uri.host, uri.port)
  if uri.to_s[0..4]=="https" then
    http.use_ssl=true
    http.verify_mode=OpenSSL::SSL::VERIFY_NONE
  end
  if params then 
      req = Net::HTTP::Delete.new("#{uri.path}?".concat(params.collect { |k,v| "#{k}=#{CGI::escape(v.to_s)}" }.join('&')), 'Content-Type' => 'application/json', 'authorization' => token)
  else
      req = Net::HTTP::Delete.new(uri.path, 'Content-Type' => 'application/json', 'authorization' => token)
  end
  res = http.request(req)
  res.body
end



def get_params(params_hash)
  params={}
  params_hash.each do |key, value| if value!=nil then params[key]=value end end
  params
end

