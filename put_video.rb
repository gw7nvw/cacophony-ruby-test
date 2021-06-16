require '~/cacophony/testing/test-harness/api_tools.rb'

def put_all_videos()
  files=`ls -1 *.list`
  files.split("\n").each do |file|
    animal=file.split('.')[0]
    put_videos(animal,'cptv')
  end
end

def put_videos(animal, format)
  if format=='mp4' then typestr='audio' else typestr='thermalRaw' end

  token=api_login("#{USERNAME}","#{PASSWORD}","test")

  group=check_group(token,'video-test')
  if !group then group=create_group(token,'video-test') end
  device=check_device(token,'video-test-'+animal,group)
  if !device then device=create_device(token,'video-test-'+animal, 'video-test')   end
 
  files=read_filenames(animal,format) 
  puts "DEBUG: uploading "+files.count.to_s+" files"
  res=nil
  files.each do |file|
    res=post_file(token,device,file,typestr,nil)
    puts "LOG: "+file+" -> new recording id: "++res['recordingId'].to_s
  end
  res
end

def clear_videos(server)
  token=api_login("#{USERNAME}","#{PASSWORD}",server)
  group=check_group(token,'video-test')
  res=delete_recordings(token,group)
  true
end

def check_videos(animal,baseline_file, output_file,compare_ai)
  if !compare_ai or compare_ai=="" then compare_ai="Master" end
  token=api_login("#{USERNAME}","#{PASSWORD}","test")
  missedCount=0
  if baseline_file then
    base_res_str=File.read(baseline_file)
    baseline=JSON.parse(base_res_str) 
  else
    baseline=nil
  end

  group=check_group(token,'video-test')
  if !group then group=create_group(token,'video-test') end
  device=check_device(token,'video-test-'+animal,group)
  if !device then device=create_device(token,'video-test-'+animal, 'video-test')   end

  recordings=get_recordings_by_device(token, device)

  tracks=[]
  @pass_count=0
  @pass_conf=0
  @fail_count=0
  @unid_count=0
  all_results={rec_count: 0, pass_count: 0, pass_conf:0, fail_count: 0, unid_count: 0, recordings: recordings, tracks: tracks, results: [] }
  recordings['rows'].each do |recording|

    if baseline then 
       baseline_recording=baseline["recordings"]['rows'].select{|row| row["recordingDateTime"]==recording["recordingDateTime"]}.first 
       if baseline_recording and baseline_recording['id'] then
         puts "DEBUG: original recording ID: "+baseline_recording['id'].to_s
         puts "DEBUG: original recording time: "+baseline_recording['recordingDateTime'].to_s
       else 
         puts "ERROR: cannot find matching record"
         missedCount+=1
       end

    else baseline_recording=nil end
    #check track data in recording
    recording_results=check_tracks(recording,animal,baseline_recording,compare_ai)

    track_json=api_recording_track_get(token,recording['id'])  
    track=JSON.parse(track_json)["tracks"] 
    tracks.push({track: track, recordingDateTime: recording["recordingDateTime"]})

    #anlayise tracking data in Tracks table
    if baseline then
      tracking_results=check_tracking(token,track,recording["recordingDateTime"],baseline['tracks'])
    else
      tracking_results=check_tracking(token,track,recording["recordingDateTime"],nil)
    end


    #match up tracks and tracking data
    combined_resuts={time: recording_results[:time], overlap_s: tracking_results[:overlap_s], track_count: recording_results[:track_count], tracks: []} 
    tracking_results[:tracks].each do |tracking|
      track=(recording_results[:tracks].select{|rr| rr[:id]==tracking[:id]}).first
      track=track.merge(tracking)
      combined_resuts[:tracks].push(track)
    end
    all_results[:results].push(combined_resuts)
    all_results[:rec_count]+=1
  end

  all_results[:pass_count]=@pass_count
  if @pass_count>0 then all_results[:pass_conf]=@pass_conf/@pass_count end
  all_results[:unid_count]=@unid_count
  all_results[:fail_count]=@fail_count

  puts "======================================="
  puts "Results for animal: "+animal
  puts "Correct IDs: "+all_results[:pass_count].to_s+if(baseline) then " --- was "+baseline["pass_count"].to_s else "" end
  puts "Mean confidence: "+all_results[:pass_conf].to_f.round(3).to_s+if(baseline) then " --- was "+baseline["pass_conf"].to_f.round(3).to_s else "" end

  puts "Unidentified: "+all_results[:unid_count].to_s+if(baseline) then " --- was "+baseline["unid_count"].to_s else "" end

  puts "Failed IDs: "+all_results[:fail_count].to_s+if(baseline) then " --- was "+baseline["fail_count"].to_s else "" end
  if missedCount>0 then 
    puts "New viedos not in previous log: "+missedCount.to_s
  end

  puts "======================================="

  if output_file and output_file.length>0 then File.open(output_file, 'w') { |file| file.write(all_results.to_json)} end

  true
end

def delete_test_data
  `sed 's/@USERSTR@/video-test%/g' ~/cacophony/ruby/test-harness/delete-script-template.sql > delete-script.sql`
  `scp delete-script.sql matt@server-test-api:`
  `ssh matt@server-test-api psql -U user10 -d cacodb -f /home/matt/delete-script.sql`
  `ssh matt@server-test-api "rm delete-script.sql"`
end

####################################

def check_tracks(rec,animal,baseline_rec,compare_ai)
    rec_res={track_count: 0, time: if rec['recordingDateTime'] then rec['recordingDateTime'] else "" end, tracks: []} 
    puts "DEBUG: Recording: "+rec['id'].to_s+" - "+rec_res[:time]
    track_count=0
    rec['Tracks'].each do |track|
      if baseline_rec then baseline_tracks=baseline_rec['Tracks'][track_count] end
      track_count+=1
      tr_id=""
      track_id=track["id"]

      tr_conf=0
      puts "DEBUG:   Track "+track['id'].to_s

      tt_count=0
      track['TrackTags'].each do |tt|
        baseline_tt=nil 
        if baseline_rec and baseline_tracks then baseline_tt=baseline_tracks['TrackTags'].select{|btt| btt['data']==tt['data']}.first end
        tt_count+=1 
        if baseline_tt then 
          puts "DEBUG:     AI: "+tt['data']+": "+debug_compare_equal(tt['what'],baseline_tt['what'])+" - "+debug_compare_greater(tt['confidence'],baseline_tt['confidence'])+" [should be: "+animal+"]"
        else
          puts "DEBUG:     AI: "+tt['data']+": "+tt['what']+" - "+tt['confidence'].to_s+" [should be: "+animal+"]"
        end

        if tt['data']=="Master" then 
           tr_id=tt['what']
           if tt['what'][0..animal.length-1]==animal then 
              @pass_count+=1
              @pass_conf+=tt['confidence']
              tr_conf=tt['confidence']
           elsif tt['what']=='unidentified' then
              @unid_count+=1
           else
              @fail_count+=1
           end
        end
      end
      track={id: track_id, identification: tr_id, confidence: tr_conf}
      rec_res[:tracks].push(track)
      rec_res[:track_count]+=1

      
    end
    rec_res
end

def check_tracking(token,tracks,recordingDateTime,baseline_tracks_by_time)
  if baseline_tracks_by_time then baseline_tracks=baseline_tracks_by_time.select{|tr| tr['recordingDateTime']==recordingDateTime}.first end
  tracks_res={count: 0, overlap_s: 0, tracks: []}
  baseline_tracks_res={count: 0, overlap_s: 0, tracks: []}
  overlap=0
  b_overlap=0
  track_count=tracks.count
  track_no=0
  tracks.each do |track|
    if baseline_tracks then baseline_track=baseline_tracks['track'][track_no] end
    track_no+=1
    id=track["id"]
    start_s=track["data"]["start_s"]
    end_s=track["data"]["frame_end"]/9
    # check for overlpas
    tracks_res[:tracks].each do |tr|
      if tr[:start_s] <= end_s && start_s<=tr[:end_s] then
        if tr[:start_s]>start_s then os=tr[:start_s] else os=start_s end 
        if tr[:end_s]<end_s then oe=tr[:end_s] else oe=end_s end 
        overlap=oe-os
      end
    end

    if baseline_tracks and baseline_track then
      b_start_s=baseline_track["data"]["start_s"]
      b_end_s=baseline_track["data"]["frame_end"]/9
      # check for overlpas
      baseline_tracks_res[:tracks].each do |tr|
        if tr[:start_s] <= b_end_s && b_start_s<=tr[:end_s] then
          if tr[:start_s]>b_start_s then b_os=tr[:start_s] else b_os=b_start_s end 
          if tr[:end_s]<end_s then b_oe=tr[:end_s] else b_oe=b_end_s end 
          b_overlap=b_oe-b_os
        end
      end
    end

    tracks_res[:tracks].push({id: id, start_s: start_s, end_s: end_s})
    tracks_res[:count]+=1
    tracks_res[:overlap_s]+=overlap
    if baseline_tracks then 
       baseline_tracks_res[:tracks].push({id: id, start_s: b_start_s, end_s: b_end_s})
       baseline_tracks_res[:count]+=1
       baseline_tracks_res[:overlap_s]+=b_overlap
       puts "DEBUG: Track: "+id.to_s+", start: "+debug_compare_equal((start_s||0).round(2).to_s,(b_start_s||0).round(2).to_s)+", end: "+debug_compare_equal((end_s||0).round(2).to_s,(b_end_s||0).round(2).to_s)
    else
       puts "DEBUG: Track: "+id.to_s+", start: "+start_s.round(2).to_s+", end: "+end_s.round(2).to_s
    end
  end
  if baseline_tracks then 
    puts "DEBUG: Tracks: "+debug_compare_equal(tracks_res[:count].to_s, baseline_tracks_res[:count].to_s)+", overlap: "+debug_compare_less(tracks_res[:overlap_s].round(2), baseline_tracks_res[:overlap_s].round(2))
  else
    puts "DEBUG: Tracks: "+tracks_res[:count].to_s+", overlap: "+tracks_res[:overlap_s].round(2).to_s
  end
  tracks_res
end

def get_recordings_by_device(token, device)
  res=api_v1_recordings(token,'{"DeviceId":['+device.to_s+']}')
  resjson=JSON.parse(res)
  puts "DEBUG: get recordings returned "+resjson["rows"].count.to_s+" rows"
  resjson
end

def delete_recordings(token, group)
  result=nil
  rows=1
  while rows>0 do
    res=api_v1_recordings(token,'{"GroupId":['+group.to_s+']}')
    resjson=JSON.parse(res)
    rows=resjson["rows"].count
    puts "DEBUG: get recordings returned "+resjson["rows"].count.to_s+" rows"
    resjson["rows"].each do |row|
      result=delete_recording(token,row["id"])
    end
  end
  result
end

def delete_recording(token,id)
  res=api_v1_recording_delete(token,id)
  resjson=JSON.parse(res)
  if resjson["success"] then
    puts "DEBUG: delete recording "+id.to_s+" succeeded"
    true
  else
    puts "DEBUG: delete recording "+id.to_s+" failed"
    false
  end
end

def check_group(token,name)
  group=nil
  res=api_groups_get(token,name) 
  resjson=JSON.parse(res)
  if resjson["errorType"] then
    group=nil
  elsif resjson["groups"] then
    group=resjson['groups'][0]['id']
  end  
  puts "DEBUG: check_group('token','#{name}' returns: '#{group}')"
  group
end

def create_group(token,name)
  group=nil
  res=api_groups_post(token,name)
  resjson=JSON.parse(res)
  if resjson["success"] then
    group=check_group(token,name)
  end
  puts "DEBUG: create_group('token','#{name}' returns: '#{group}')"
  group
end

def check_device(token,deviceName,group)
  device=nil

  res=api_v1_devices(token,deviceName,group.to_s)
  resjson=JSON.parse(res)
  if resjson["success"] then
     device=resjson["device"]["id"]
  end
  puts "DEBUG: check_device('token','#{deviceName}','#{group}' returns: '#{device}')"

  device
end

def create_device(token,deviceName,groupName)
  device=nil
  res=api_devices_post(token,deviceName,groupName)
  resjson=JSON.parse(res)
  if resjson["success"] then
    device=resjson['id']
  end 
  puts "DEBUG: create_device('token','#{deviceName}','#{groupName}' returns: '#{device}')"
  device
end

def read_filenames(animal,format)
  filenames=[]
  list=`ls -1 #{animal}/#{animal}*.#{format}`
  list.split("\n").each do |l|
    filenames << l
  end
  filenames
end

def post_file(token,device,file,typestr,filehash)
  puts "uploading "+file
  res=api_v1_recordings_devicePOST(token,device,file,typestr,filehash)
  @res=res
  resjson=JSON.parse(res)
  if resjson['success'] then
    puts "DEBUG: post_file(token,'#{device}','#{file}' returns SUCCESS"
    puts "DEBUG: post_file(token,'#{device}','#{file}' returns RecordingId: "+resjson['recordingId'].to_s 
    true
  else
    puts "DEBUG: post_file(token,'#{device}','#{file}' returns ERROR: "+res#json['message']
    false
  end
  resjson
end

def debug_compare_equal(current, previous)
  if current==previous then current+"(=)" else "ERROR: was "+previous+" now "+current+" FAIL" end
end

def debug_compare_less(current, previous)
  if current==previous then 
    current.to_s+"(=)" 
  elsif current<previous then 
    current.to_s+"(<"+previous.to_s+")" 
  else
    "ERROR: was "+previous.to_s+" now "+current.to_s+" INCREASE" 
  end
end

def debug_compare_greater(current, previous)
  if current==previous then 
    current.to_s+"(=)" 
  elsif current>previous then 
    current.to_s+"(>"+previous.to_s+")" 
  else
    "ERROR: was "+previous.to_s+" now "+current.to_s+" DECREASE" 
  end
end

def confusion_matrix(filedate, ainame)
    #get animals list
    animals=[]
    files=`ls *-#{filedate}`
    files.lines.each do |file|
      animal=file.split('-')[0]
      if animal=='false' then animal='false-positives' end
      animals.push(animal)
    end
    animals.push('unidentified')

    #create blank matrix
    matrix={}
    animals.each do |a1|
      matrix[a1]={}
      animals.each do |a2|
        matrix[a1][a2]=0
      end
    end

    
    animals.each do |animal|
      if animal!="unidentified" then
        if animal=='false-positives' then
          filename="false-positive-"+filedate
        else
          filename=animal+"-"+filedate
        end
  
        base_res_str=File.read(filename)
        baseline=JSON.parse(base_res_str)
        
        baseline['recordings']['rows'].each do |recording|
          recording['Tracks'].each do |track|
            track['TrackTags'].each do |tt|
              if tt['data']==ainame then
                matrix[animal][tt['what']]+=1
              end
            end
          end
        end
      end
    end

    puts "#,"+animals.join(',')
    count=0
    matrix.each do |row|
      puts (animals[count]||"")+","+row[1].map{ |key,value| value}.join(',')
      count+=1
    end
  matrix
end

