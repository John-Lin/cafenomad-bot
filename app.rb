#!/bin/env ruby
# encoding: utf-8

require 'sinatra'
require 'line/bot'
require 'http'
require 'json'
require 'geokit'

configure :development, :test do
  require 'config_env'
  ConfigEnv.path_to_config("#{__dir__}/config/config_env.rb")
end

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

get '/ping' do
  "PONG"
end

post '/callback' do
  body = request.body.read

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    error 400 do 'Bad Request' end
  end

  events = client.parse_events_from(body)

  events.each { |event|
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Location
        latitude = event.message['latitude']
        longitude = event.message['longitude']
        address = event.message['address']

        current_location = Geokit::LatLng.new(latitude, longitude)
        Geokit::default_units = :meters

        response = HTTP.get('https://cafenomad.tw/api/v1.0/cafes').to_s
        response_json = JSON.parse(response)
        # puts response_json
        feedback = {}
        coffees_columns = []
        coffee_shops = []

        response_json.each do |c|
          dest_str = "#{c["latitude"]},#{c["longitude"]}"
          distance_ms = current_location.distance_to(dest_str)
          if distance_ms <= 1000
            c['distance_ms'] = distance_ms
            coffee_shops << c
          end
        end

        sorted_coffee_shops = coffee_shops.sort_by { |x| x['distance_ms'] }

        sorted_coffee_shops[0..4].each do |scs|
          if scs['url'] == ""
            office_site_hash = { type: 'message', label: 'Official Site', text: '目前並沒有提供官方網站' }
          else
            office_site_hash = { type: 'uri', label: 'Official Site', uri: scs['url'] }
          end

          coffees_columns << {
            # thumbnailImageUrl: 'https://bot2line.herokuapp.com/img/coffee',
            title: scs['name'],
            text: "#{scs['address']}\n#{scs['distance_ms'].round} 公尺",
            actions: [
              {
                type: 'uri',
                label: 'View on Cafenomad',
                uri: "https://cafenomad.tw/shop/#{scs['id']}"
              },
              {
                type: 'uri',
                label: 'Google Map',
                uri: "https://www.google.com/maps/dir/Current+Location/#{scs["latitude"]},#{scs["longitude"]}"
              },
              office_site_hash
            ]
          }
        end

        feedback  = {
          type: 'template',
          altText: '電腦版尚未支援，或是 LINE 沒有更新到最新版。',
          template: {
            type: 'carousel',
            columns: coffees_columns
          }
        }
        if coffees_columns.empty?
          reply event, textmsg('這附近似乎沒有咖啡廳呢！')
        else
          p coffees_columns
          reply event, feedback
        end

      when Line::Bot::Event::MessageType::Join
        reply event, textmsg('你好！歡迎使用 Cafe Nomad 小幫手')
      when Line::Bot::Event::MessageType::Text
        message = {
          type: 'text',
          text: event.message['text']
        }

      when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
        reply event, textmsg("謝謝分享，但我現在還看不懂圖片與影片呢。")
      end
    end
  }

  "OK"
end

def textmsg text
  if text.is_a? String
    return {
      type: 'text',
      text: text
    }
  end

  # it is probably already wrapped. Skip wrapping with type.
  return text
end

def reply event, data
  client.reply_message event['replyToken'], data
  p data
end
