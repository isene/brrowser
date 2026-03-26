module Brrowser
  class Tab
    attr_accessor :url, :title, :content, :ix, :links, :forms, :images
    attr_reader :back_history, :forward_history

    def initialize(url = nil)
      @url             = url
      @title           = ""
      @content         = ""
      @ix              = 0
      @links           = []
      @forms           = []
      @images          = []
      @back_history    = []
      @forward_history = []
    end

    def navigate(new_url)
      if @url
        @back_history.push({ url: @url, ix: @ix })
      end
      @forward_history.clear
      @url = new_url
      @ix  = 0
    end

    def go_back
      return nil if @back_history.empty?
      @forward_history.push({ url: @url, ix: @ix })
      prev = @back_history.pop
      @url = prev[:url]
      @ix  = prev[:ix]
      @url
    end

    def go_forward
      return nil if @forward_history.empty?
      @back_history.push({ url: @url, ix: @ix })
      nxt = @forward_history.pop
      @url = nxt[:url]
      @ix  = nxt[:ix]
      @url
    end

    def can_go_back?    = !@back_history.empty?
    def can_go_forward? = !@forward_history.empty?
  end
end
