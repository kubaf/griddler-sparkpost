require 'mail'

module Griddler
  module Sparkpost
    class Adapter
      def initialize(params)
        @params = params
      end

      def self.normalize_params(params)
        adapter = new(params)
        adapter.normalize_params
      end

      def normalize_params
        msg = params['_json'][0]['msys']['relay_message']
        content = msg['content']
        mail = Mail.read_from_string(content['email_rfc822'])
        raw_headers = headers_raw(content['headers'])
        headers_hash = extract_headers(raw_headers)
        # SparkPost documentation isn't clear on friendly_from.
        # In case there's a full email address (e.g. "Test User <test@test.com>"), strip out junk
        # clean_from = msg['friendly_from'].split('<').last.delete('>').strip
        # Actually we don't trust their clean_from and use original header to get
        # full name since they appear to strip it
        clean_from = headers_hash['From']
        clean_rcpt = msg["rcpt_to"] #.split('<').last.delete('>').strip
        to_addresses = Array.wrap(content['to']) << clean_rcpt
        params.merge(
          to: to_addresses.compact.uniq,
          from: clean_from,
          cc: content['cc'].nil? ? [] : content['cc'],
          subject: content['subject'],
          text: content['text'],
          html: content['html'],
          headers: raw_headers, # spec calls for raw headers, so convert back
          attachments: attachment_files(mail)
        )
      end

      private

      attr_reader :params

      def extract_headers(raw_headers)
        if raw_headers.is_a?(Hash)
          raw_headers
        else
          header_fields = Mail::Header.new(raw_headers).fields

          header_fields.inject({}) do |header_hash, header_field|
            header_hash[header_field.name.to_s] = header_field.value.to_s
            header_hash
          end
        end
      end

      def headers_raw(arr)
        # sparkpost gives us an array of header maps, with just one key and value (to preserve order)
        # we will convert them back to the raw headers here
        arr.inject([]) { |raw_headers, obj|
          raw_headers.push("#{obj.keys.first}: #{obj.values.first}")
        }.join("\r\n")
      end

      def attachment_files(mail)
        mail.attachments.map { |attachment|
          ActionDispatch::Http::UploadedFile.new({
            filename: attachment.filename,
            type: attachment.mime_type,
            tempfile: create_tempfile(attachment)
          })
        }
      end

      def create_tempfile(attachment)
        filename = attachment.filename.gsub(/\/|\\/, '_')
        tempfile = Tempfile.new(filename, Dir::tmpdir, encoding: 'ascii-8bit')
        content = attachment.body.decoded
        tempfile.write(content)
        tempfile.rewind
        tempfile
      end
    end
  end
end
