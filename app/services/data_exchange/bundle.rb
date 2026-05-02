# frozen_string_literal: true

require "json"
require "zlib"
require "stringio"

module DataExchange
  # Bundle envelope — manifest + per-resource payload, gzipped JSON, then
  # passphrase-encrypted via BundleCipher. The envelope is the only thing
  # that ever crosses an instance boundary.
  #
  # Wire pipeline:
  #   { manifest:, payload: } → JSON.dump → gzip → BundleCipher.encrypt → blob
  #
  # Reverse on import. Sensitive payload (decrypted ciphertext from source
  # records) lives in plaintext inside the gzipped JSON, which is why the
  # outer encryption is non-negotiable.
  class Bundle
    FORMAT_VERSION = 1
    InvalidFormat  = Class.new(StandardError)

    attr_reader :manifest, :payload

    def self.build(manifest:, payload:)
      new(manifest: manifest, payload: payload)
    end

    def self.dump(manifest:, payload:, passphrase:)
      json = JSON.generate({ "manifest" => manifest, "payload" => payload })
      gz   = gzip(json)
      BundleCipher.encrypt(gz, passphrase: passphrase)
    end

    def self.load(blob, passphrase:)
      gz   = BundleCipher.decrypt(blob, passphrase: passphrase)
      json = gunzip(gz)
      data = JSON.parse(json)

      manifest = data.fetch("manifest") { raise InvalidFormat, "missing manifest" }
      payload  = data.fetch("payload")  { raise InvalidFormat, "missing payload" }

      validate_format_version!(manifest)

      new(manifest: manifest, payload: payload)
    rescue JSON::ParserError => e
      raise InvalidFormat, "bundle JSON invalid: #{e.message}"
    end

    def self.gzip(str)
      io = StringIO.new
      io.set_encoding(Encoding::ASCII_8BIT)
      gz = Zlib::GzipWriter.new(io)
      gz.write(str)
      gz.close
      io.string
    end

    def self.gunzip(blob)
      Zlib::GzipReader.new(StringIO.new(blob)).read
    end

    def self.validate_format_version!(manifest)
      v = manifest["format_version"]
      return if v == FORMAT_VERSION

      raise InvalidFormat,
            "unsupported bundle format_version=#{v.inspect} " \
            "(this build understands #{FORMAT_VERSION})"
    end

    def initialize(manifest:, payload:)
      @manifest = manifest
      @payload  = payload
    end

    def resource_keys
      payload.keys.map(&:to_sym)
    end

    def records_for(resource_key)
      payload.fetch(resource_key.to_s, [])
    end
  end
end
