# frozen_string_literal: true

require "openssl"

module DataExchange
  # AES-256-GCM with key derived from a user-supplied passphrase via PBKDF2.
  # Salt + IV + tag are stored in the envelope (see #pack), passphrase is
  # never persisted. GCM auth tag = automatic passphrase verification on
  # decrypt - wrong passphrase raises with a clean error.
  class BundleCipher
    InvalidPassphrase = Class.new(StandardError)
    MalformedBundle   = Class.new(StandardError)

    MAGIC      = "OBRX1"
    KEY_BYTES  = 32
    SALT_BYTES = 16
    IV_BYTES   = 12
    TAG_BYTES  = 16
    PBKDF2_ITER = 200_000    # ~150ms on a modern laptop, intentionally slow

    def self.encrypt(plaintext, passphrase:)
      new(passphrase).encrypt(plaintext)
    end

    def self.decrypt(blob, passphrase:)
      new(passphrase).decrypt(blob)
    end

    def initialize(passphrase)
      raise ArgumentError, "passphrase required" if passphrase.to_s.empty?

      @passphrase = passphrase
    end

    def encrypt(plaintext)
      salt = SecureRandom.random_bytes(SALT_BYTES)
      iv   = SecureRandom.random_bytes(IV_BYTES)
      key  = derive_key(salt)

      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = key
      cipher.iv  = iv
      cipher.auth_data = MAGIC
      ct = cipher.update(plaintext) + cipher.final
      tag = cipher.auth_tag(TAG_BYTES)

      pack(salt, iv, tag, ct)
    end

    def decrypt(blob)
      salt, iv, tag, ct = unpack(blob)
      key = derive_key(salt)

      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = key
      cipher.iv  = iv
      cipher.auth_tag = tag
      cipher.auth_data = MAGIC

      cipher.update(ct) + cipher.final
    rescue OpenSSL::Cipher::CipherError
      # GCM tag mismatch - wrong passphrase or tampered blob. Don't leak
      # which one.
      raise InvalidPassphrase, "wrong passphrase or corrupted bundle"
    end

    private

    def derive_key(salt)
      OpenSSL::KDF.pbkdf2_hmac(
        @passphrase,
        salt: salt,
        iterations: PBKDF2_ITER,
        length: KEY_BYTES,
        hash: "sha256"
      )
    end

    # Wire layout (binary):
    #   MAGIC (5B) | salt (16B) | iv (12B) | tag (16B) | ciphertext (rest)
    def pack(salt, iv, tag, ct)
      MAGIC + salt + iv + tag + ct
    end

    def unpack(blob)
      raise MalformedBundle, "bundle too short" if blob.bytesize < MAGIC.bytesize + SALT_BYTES + IV_BYTES + TAG_BYTES
      raise MalformedBundle, "bad magic" unless blob.byteslice(0, MAGIC.bytesize) == MAGIC

      offset = MAGIC.bytesize
      salt   = blob.byteslice(offset, SALT_BYTES);   offset += SALT_BYTES
      iv     = blob.byteslice(offset, IV_BYTES);     offset += IV_BYTES
      tag    = blob.byteslice(offset, TAG_BYTES);    offset += TAG_BYTES
      ct     = blob.byteslice(offset, blob.bytesize - offset)

      [ salt, iv, tag, ct ]
    end
  end
end
