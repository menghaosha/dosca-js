class Application
  ROOT_CONTROLLER = "login"
  DEFAULT_ACTION = "index"

  class << self
    def get_controller_and_action_name
      url_split = ENV["REQUEST_URI"].split("/").delete_if{|element| element.empty?}
      controller = url_split[1] || ROOT_CONTROLLER
      action = url_split[2] || DEFAULT_ACTION
      action = action.split("?")[0] unless  action.index("?").nil?
      {:controller => controller, :action => action}
    end

    def symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)
      hash.inject({}){|new_hash, key_value|
        key, value = key_value
        value = symbolize_keys(value) if value.is_a?(Hash)
        value = value.map{|item| symbolize_keys(item)} if value.is_a?(Array) 
        new_hash[key.to_sym] = value
        new_hash
      }
    end
  end
end
