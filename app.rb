require "rubygems"

gem "ramaze", "2011.10.23"
require "ramaze"

# Ramaze::Log.ignored_tags = [:debug, :info]

require "base64"

require "json"
require "juggernaut"

require "mongoid"
Mongoid.configure do |config|
  config.master = Mongo::Connection.new.db("canvas_vroy_ca")
end

class Coordinate
  include Mongoid::Document
  
  field :canvas, type: String
  field :x, type: String
  field :y, type: String
  field :color, type: String
  field :shape, type: String
  field :size, type: String

  def self.clear(canvas)
    Coordinate.where(canvas: canvas).delete_all
  end
  def self.load(canvas)
    Coordinate.where(canvas: canvas).map do |coord|
      [ coord.x, coord.y, coord.color, coord.shape, coord.size ]
    end
  end
end

class MainController < Ramaze::Controller
  map '/'

  def index(canvas="index")
    @canvas = canvas
  end
  
  def load(canvas)
    return Coordinate.load(canvas).to_json
  end

  def clear(canvas)
    Coordinate.clear(canvas)
    Juggernaut.publish( canvas, { :action => "clear" } )
    return true.to_json
  end

  # Action to receive clicks via AJAX posts.
  # Expects an array of coordinates in the "clicks" key: [ [x1,y1,color,shape,size], [x2,y2,color,shape,size], [x3,y3,color,shape,size] ]
  # Expects a string to identify the canvas in the "canvas" key.
  def click
    canvas = request[:canvas]

    clicks = request[:clicks].map{|x| x.last }
    clicks.each do |click|
      Coordinate.create(:canvas => canvas,
                        :x => click[0],
                        :y => click[1],
                        :color => click[2],
                        :shape => click[3],
                        :size => click[4])
    end
      
    Juggernaut.publish(canvas, clicks, :except => request.env["HTTP_X_SESSION_ID"])
  end

  def save_image
    canvas_name = h(request[:canvas_name])

    # See http://www.permadi.com/blog/2010/10/html5-saving-canvas-image-data-using-php-and-ajax/
    # for information about the base64 operation
    image = Base64.decode64( request[:image].split(",").last )

    File.open("saved_images/#{canvas_name}.png", "w") {|f| f.write(image) }

    return { :filename => "/download_image/#{canvas_name}.png" }.to_json
  end

  def download_image(canvas_name)
    send_data_as_file( File.read("saved_images/#{h(canvas_name)}"), "#{h(canvas_name)}", "image/png" )
  end

  private

  # Based on a more recent version of the send_file helper.
  # https://github.com/Ramaze/ramaze/blob/a96af85d1572b6bf06ee1e1d58d576db25c78af0/lib/ramaze/helper/send_file.rb
  def send_data_as_file(data, filename, content_type)
    response.body = [data]
    response['Content-Length'] = data.bytesize.to_s
    response['Content-Type'] = content_type
    response['Content-Disposition'] = "Content-disposition: attachment; filename=#{filename}"
    response.status = 200

    throw(:respond, response)
  end
end
