class PagesController < ApplicationController

  allow_unauthenticated_access only: %i[awaiting_activation]

  def awaiting_activation
    @email = params[:email].presence
  end

  def home
    if authenticated?
      redirect_to user_path(current_user)
    else
      if Server.count == 0
        Server.create(name: '')
        # helpers.annotations_setup([])
      end
      @server = Server.new
      @failed = true # prevents repeated checking of the db in views
      @title = "Home"
      @user = User.new
    end
  end

  def versions
    @git = `git log | head -3`.chomp.split("\n")
    @tag = `git describe`
    @gems = `cat Gemfile.lock`
  end

  def echo
    respond_to do |format|
      format.json do
        render json: { time: Time.now.to_s, version: 2 }
      end
      format.html do
        render plain: Time.now.to_s
      end
    end
  end
  def azure_audio_url
    return render json: { error: 'Not authenticated' }, status: 401 unless authenticated?

    blob_name = params[:blob_name]
    return render json: { error: 'blob_name required' }, status: 400 if blob_name.blank?

    begin
      storage_account_name = Rails.application.credentials.dig(:azure_storage, :storage_account_name)
      storage_access_key = Rails.application.credentials.dig(:azure_storage, :storage_access_key)
      container_name = Rails.application.credentials.dig(:azure_storage, :container)

      return render json: { error: 'Azure Storage credentials not configured' }, status: 500 if storage_account_name.blank? || storage_access_key.blank? || container_name.blank?

      signed_url = build_azure_blob_sas_url(storage_account_name, storage_access_key, container_name, blob_name)

      render json: {
        url: signed_url,
        blob_name: blob_name,
        container: container_name
      }

    rescue => e
      Rails.logger.error "Azure audio URL error: #{e.message}"
      Rails.logger.error e.backtrace
      render json: {
        error: 'Failed to generate signed URL',
        details: e.message
      }, status: 500
    end
  end

  def azure_transcribe
    return render json: { error: 'Not authenticated' }, status: 401 unless authenticated?
    
    blob_name = params[:blob_name]
    return render json: { error: 'blob_name required' }, status: 400 if blob_name.blank?

    begin
      storage_account_name = Rails.application.credentials.dig(:azure_storage, :storage_account_name)
      storage_access_key = Rails.application.credentials.dig(:azure_storage, :storage_access_key)
      container_name = Rails.application.credentials.dig(:azure_storage, :container)
      speech_key = Rails.application.credentials.dig(:azure_speech, :key)
      speech_region = Rails.application.credentials.dig(:azure_speech, :region)

      return render json: { error: 'Azure credentials not configured' }, status: 500 if storage_account_name.blank? || storage_access_key.blank? || container_name.blank?
      return render json: { error: 'Azure Speech credentials not configured' }, status: 500 if speech_key.blank? || speech_region.blank?

      audio_url = build_azure_blob_sas_url(storage_account_name, storage_access_key, container_name, blob_name)

      transcription_result = transcribe_audio_from_url(audio_url, speech_key, speech_region)
      
      render json: {
        transcription: transcription_result,
        blob_name: blob_name,
        status: 'success'
      }
      
    rescue => e
      Rails.logger.error "Azure transcription error: #{e.message}"
      Rails.logger.error e.backtrace
      render json: { 
        error: 'Failed to transcribe audio', 
        details: e.message
      }, status: 500
    end
  end

  private


  def transcribe_audio_from_url(audio_url, speech_key, speech_region)
    # Use Azure Speech Services Batch Transcription API
    batch_api_url = "https://#{speech_region}.api.cognitive.microsoft.com/speechtotext/v3.1/transcriptions"
    
    # Step 1: Create transcription job
    http = Net::HTTP.new(URI(batch_api_url).host, 443)
    http.use_ssl = true
    http.read_timeout = 30  # 30 second timeout for individual HTTP requests
    http.open_timeout = 10  # 10 second timeout for connection
    
    request = Net::HTTP::Post.new(batch_api_url)
    request['Ocp-Apim-Subscription-Key'] = speech_key
    request['Content-Type'] = 'application/json'
    
    request.body = {
      'contentUrls' => [audio_url],
      'locale' => 'en-US',
      'displayName' => 'Audio Transcription',
      'properties' => {
        'diarizationEnabled' => false,
        'punctuationMode' => 'DictatedAndAutomatic',
        'profanityFilterMode' => 'None'
      }
    }.to_json
    
    Rails.logger.info "Creating batch transcription job..."
    response = http.request(request)
    
    unless response.code.to_i == 201
      Rails.logger.error "Failed to create transcription job: #{response.code} - #{response.body}"
      return "Error creating transcription job: #{response.code} - #{response.body}"
    end
    
    job_data = JSON.parse(response.body)
    job_url = job_data['self']
    Rails.logger.info "Transcription job created: #{job_url}"
    
    # Step 2: Poll for completion (with timeout)
    max_wait_time = 120 # 2 minutes timeout (reduced to avoid gateway timeouts)
    start_time = Time.current
    
    loop do
      if Time.current - start_time > max_wait_time
        return "Transcription timeout after #{max_wait_time} seconds"
      end
      
      sleep(5) # Wait 5 seconds between polls
      
      # Check job status
      status_request = Net::HTTP::Get.new(job_url)
      status_request['Ocp-Apim-Subscription-Key'] = speech_key
      status_response = http.request(status_request)
      
      unless status_response.code.to_i == 200
        Rails.logger.error "Failed to get job status: #{status_response.code}"
        return "Error checking transcription status"
      end
      
      status_data = JSON.parse(status_response.body)
      Rails.logger.info "Job status: #{status_data['status']}"
      
      case status_data['status']
      when 'Succeeded'
        # Get transcription results
        files_url = status_data['links']['files']
        Rails.logger.info "Getting files from: #{files_url}"
        
        files_request = Net::HTTP::Get.new(files_url)
        files_request['Ocp-Apim-Subscription-Key'] = speech_key
        files_response = http.request(files_request)
        
        if files_response.code.to_i == 200
          files_data = JSON.parse(files_response.body)
          Rails.logger.info "Files data: #{files_data.inspect}"
          
          result_file = files_data['values']&.find { |f| f['kind'] == 'Transcription' }
          Rails.logger.info "Found result file: #{result_file.inspect}"
          
          if result_file && result_file['links'] && result_file['links']['contentUrl']
            # Download transcription result
            content_url = result_file['links']['contentUrl']
            Rails.logger.info "Downloading from: #{content_url}"
            
            # Parse the full URL for the download request
            content_uri = URI(content_url)
            content_http = Net::HTTP.new(content_uri.host, content_uri.port)
            content_http.use_ssl = content_uri.scheme == 'https'
            content_http.read_timeout = 30
            content_http.open_timeout = 10
            
            result_request = Net::HTTP::Get.new(content_uri.path + (content_uri.query ? "?#{content_uri.query}" : ""))
            result_request['Ocp-Apim-Subscription-Key'] = speech_key
            result_response = content_http.request(result_request)
            
            Rails.logger.info "Download response: #{result_response.code}"
            if result_response.code.to_i == 200
              transcription_data = JSON.parse(result_response.body)
              Rails.logger.info "Transcription data structure: #{transcription_data.keys.inspect}"
              
              # Try multiple possible result formats
              if transcription_data['combinedRecognizedPhrases']&.any?
                text = transcription_data['combinedRecognizedPhrases'].first['display']
                Rails.logger.info "Found text in combinedRecognizedPhrases: #{text}"
                return text if text.present?
              end
              
              if transcription_data['recognizedPhrases']&.any?
                text = transcription_data['recognizedPhrases'].map { |p| p['nBest']&.first&.dig('display') }.compact.join(' ')
                Rails.logger.info "Found text in recognizedPhrases: #{text}"
                return text if text.present?
              end
              
              Rails.logger.error "No transcription text found in data: #{transcription_data.inspect}"
              return "No transcription text found in response data"
            else
              Rails.logger.error "Failed to download transcription: #{result_response.code} - #{result_response.body}"
              return "Failed to download transcription results: #{result_response.code}"
            end
          else
            Rails.logger.error "No transcription file found in files response"
            return "No transcription file found in results"
          end
        else
          Rails.logger.error "Failed to get files: #{files_response.code} - #{files_response.body}"
          return "Failed to get transcription files: #{files_response.code}"
        end
        
      when 'Failed'
        return "Transcription failed: #{status_data['statusMessage'] || 'Unknown error'}"
        
      when 'Running', 'NotStarted'
        Rails.logger.info "Transcription in progress..."
        # Continue polling
        
      else
        Rails.logger.warn "Unknown status: #{status_data['status']}"
      end
    end
  end

end
