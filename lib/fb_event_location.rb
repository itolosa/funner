require 'time'
require 'json'
require 'net/http'
require 'thread'

class FbEventLocation
  def initialize(token)
    @access_token = token
  end

  def calculateStarttimeDifference(currentTime, dataString)
    return Time.parse(dataString).to_i-currentTime.to_i
  end

  def haversineDistance(coords1, coords2, isMiles)

    def toRad(x)
      return x * Math::PI / 180
    end

    lon1 = coords1[1]
    lat1 = coords1[0]

    lon2 = coords2[1]
    lat2 = coords2[0]

    r = 6371

    x1 = lat2 - lat1
    dLat = toRad(x1)
    x2 = lon2 - lon1
    dLon = toRad(x2)
    a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2)
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    d = r * c

    if (isMiles)
      d /= 1.60934
    end

    return d
  end

  def get_parallel(urls, thread_count=5, use_ssl=true)
    queue_in = Queue.new
    queue_out = Queue.new
    results = []
    urls.map { |url| queue_in << url }
    threads = thread_count.times.map do
      Thread.new do
        Net::HTTP.start('graph.facebook.com', use_ssl: use_ssl) do |http|
          while !queue_in.empty? && (url=queue_in.pop)
            uri = URI(url)
            request = Net::HTTP::Get.new(uri)
            response = http.request request
            queue_out.push(response.body)
          end
        end
      end
    end
    threads.each(&:join)
    queue_out.size.times do |resp|
      results << queue_out.pop
    end
    return results
  end

  def get_single(url, use_ssl=true)
    uri = URI(url)
    responseBody = nil
    Net::HTTP.start(uri.host, use_ssl: use_ssl) do |http|
      request = Net::HTTP::Get.new(uri)
      response = http.request request
      responseBody = response.body
    end
    return responseBody
  end

  def search(lat, lng, dist, query_sort=nil)
    access_token = @access_token
    idLimit = 50 #FB only allows 50 ids per /?ids= call
    currentTimestamp = Time.now.to_i.to_s
    venuesCount = 0
    venuesWithEvents = 0
    eventsCount = 0
    placeUrl = "https://graph.facebook.com/v2.5/search?type=place&q=*&center=#{lat},#{lng}&distance=#{dist}&limit=1000&fields=id&access_token=#{access_token}"
    responseBody = get_single(placeUrl)
    data = JSON.parse(responseBody)['data']
    venuesCount = data.length
    ids = data.collect{|v| v['id']}.each_slice(idLimit).to_a
    urls = []
    ids.each do |idArray|
      urls << "https://graph.facebook.com/v2.5/?ids=#{idArray.join(",")}&fields=id,name,cover.fields(id,source),picture.type(large),location,events.fields(id,name,cover.fields(id,source),picture.type(large),description,start_time,attending_count,declined_count,maybe_count,noreply_count).since(#{currentTimestamp})&access_token=#{access_token}"
    end
    results = get_parallel(urls, urls.length)
    events = []

    results.each do |resStr|
      resObj = JSON.parse(resStr)
      resObj.each do |venueId, venue|
        if venue['events'] and venue['events']['data'].length > 0
          venuesWithEvents += 1
          venue['events']['data'].each do |event|
            eventResultObj = {
              venueId: venueId,
              venueName: venue['name'],
              venueCoverPicture: (venue['cover'] ? venue['cover']['source'] : nil),
              venueProfilePicture: (venue['picture'] ? venue['picture']['data']['url'] : nil),
              venueLocation: (venue['location'] ? venue['location'] : nil),
              eventId: event['id'],
              eventName: event['name'],
              eventCoverPicture: (event['cover'] ? event['cover']['source'] : nil),
              eventProfilePicture: (event['picture'] ? event['picture']['data']['url'] : nil),
              eventDescription: (event['description'] ? event['description'] : nil),
              eventStarttime: (event['start_time'] ? event['start_time'] : nil),
              eventDistance: (venue['location'] ? (haversineDistance([venue['location']['latitude'], venue['location']['longitude']], [lat, lng], false)*1000).to_i : nil),
              eventTimeFromNow: calculateStarttimeDifference(currentTimestamp, event['start_time']),
              eventStats: {
                attendingCount: event['attending_count'],
                declinedCount: event['declined_count'],
                maybeCount: event['maybe_count'],
                noreplyCount: event['noreply_count']
              }
            }
            events << eventResultObj
            eventsCount += 1
          end
        end
      end
    end

    events.sort_by{ |event| event[query_sort] } if events.first.has_key?(query_sort)

    return {events: events, metadata: {venues: venuesCount, venuesWithEvents: venuesWithEvents, events: eventsCount}}
  end
end