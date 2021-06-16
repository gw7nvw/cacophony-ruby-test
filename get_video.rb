require '/home/mbriggs/cacophony/testing/test-harness/api_tools.rb'

def get_recordings(animal, type)
    idfile=animal+".list"
    label=animal+"_"
    ids=[]
    idtext=File.open(idfile).read
    idtext.each_line do |line|
      ids<<line
    end

    ids.each do |id|
      if id.to_i>0 then 
        get_recording(type,id.to_i.to_s,label)
      end
    end
end



def get_recording(type,id,label)
  if label==nil  then label="" end
  token=api_login("mbriggs","cacDog3l!fe", "prod")
    file=api_v1_recording_get(token,id)
    if type=="mp4" then
      filetoken=JSON.parse(file)["downloadFileJWT"]
      if filetoken then
        filedata=api_v1_signedurl(filetoken)
        File.open(label+id.to_s+'.mp4', 'w') { |file| file.write(filedata.force_encoding("UTF-8")) }
        puts label+id.to_s+'.mp4'
      else
        puts "ERROR: cannot find recording "+id.to_s
      end
    else
      if type=="audio" then suffix=".mp4" else suffix=".cptv" end
      filetoken=JSON.parse(file)["downloadRawJWT"]
      if filetoken then
        filedata=api_v1_signedurl(filetoken)
        File.open(label+id.to_s+suffix, 'w') { |file| file.write(filedata.force_encoding("UTF-8")) }
        puts label+id.to_s+suffix
      else
        puts "ERROR: cannot find recording "+id.to_s
      end
    end
end
