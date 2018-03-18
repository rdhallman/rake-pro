class Hash
  def recursive_merge(new_hash)
    self.merge(new_hash) do |k, old_val, new_val|
      if new_val.respond_to?(:blank) && new_val.blank?
        old_val
      elsif (old_val.kind_of?(Hash) and new_val.kind_of?(Hash))
        old_val.recursive_merge(new_val)
      else
        new_val
      end
    end
  end

  def recursive_merge!(new_hash)
    self.merge!(new_hash) do |k, old_val, new_val|
      if new_val.respond_to?(:blank) && new_val.blank?
        old_val
      elsif (old_val.kind_of?(Hash) and new_val.kind_of?(Hash))
        old_val.recursive_merge!(new_val)
      else
        new_val
      end
    end
  end

  def match strings
    select { |key,val|
      is_match = false
      strings.each { |findstr|
        is_match ||= key.downcase.include?(findstr) || val.downcase.include?(findstr)
      }
      is_match
    }
  end

  def symbolize_keys
    inject({}) { |memo,(k,v)| 
      memo[k.to_sym] = v.is_a?(Hash) ? v.symbolize_keys : v;
      memo
    }
  end


  # CASE
  #   admin@dev,prod:
  #      username: abc
  #      password
  # returns 
  #   scopes  : [dev, prod]
  #   sub_key : admin
  #   admin:
  #      username: abc
  #
  # CASE:
  # dev:
  #     url:  abc
  #   
  # returns
  #   scopes: [dev]
  #   subkey: nil
  #
  # CASE:
  #   url@dev: abc
  # 
  # returns:
  #   scopes: [dev]
  #   subkey: url
  #
  # CASE:
  #   dev:
  #       url:  abc
  #   

  def key_details(k)
    subkey = scopes = nil
    sk = k.to_s
    skp = sk.split('@')
    subkey = skp.shift.to_sym if (skp.length > 1)
    scopes = skp[0].split(/\s*[&,\|]\s*/)
    [scopes.map { |scope| scope.to_sym }, subkey]
  end

  def promote_key pk
    pk = pk.to_sym
    coh = {}
    promoted = false
    self.each_pair { |k, v|
      scopes, subkey = key_details(k)
      if (scopes.include?(pk))
        promoted = true
        if subkey.nil?
          v.each_pair { |sk, sv|
            coh[sk] = sv
          }
          coh[k] = v
        else
          coh[subkey] =v
        end
      else
        if v.is_a?(Hash)
          coh[k], subpromo = v.promote_key(pk)
          promoted |= subpromo
        else
          coh[k] = v
        end
      end
    }
    [coh, promoted]
  end

  def prune_keys pks
    coh = {}
    self.each_pair { |k, v|
      scopes, subkey = key_details(k)
      prune = false
      scopes.each { |scope| prune |= pks.include?(scope) }
      if prune
        scopes.each { |scope|
          if !pks.include?(scope)
            if (subkey.nil?)
              coh[scope] = v
            else
              coh[scope] = {}
              coh[scope][subkey] = v
            end
          end
        }
      else
        coh[k] = v.is_a?(Hash) ? v.prune_keys(pks) : v
      end
    }
    coh
  end

end
