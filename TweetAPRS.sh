#!/bin/sh

#  TweetAPRS.sh
#
#  Created by Matthew Chambers on 10/10/17.
#

# note: all console output will actually be saved to TweetAPRS.log when executed by cron

# set a few important vars
aprsCall="APRS Callsign"
aprsApiKey="APRS.fi API Key"
hereApiKey="here Geocode API Key"
wx_ApiKey="Open Weather Maps API Key"
bitly_token="Bitly Generic API Token"

# print start date/time of processing to console
startTime=$(date)
echo "TweetAPRS processing $aprsCall started at $startTime"

# cURL get latest location packet from aprs.fi
curl -s "https://api.aprs.fi/api/get?name=$aprsCall&what=loc&apikey=$aprsApiKey&format=json" > $aprsCall-myAPRS.json

# parse JSON of current and previous posit packet into string variables needed for comparision
time=$(cat $aprsCall-myAPRS.json | jq --raw-output '.entries[0].time')
lasttime=$(cat $aprsCall-myAPRS.json | jq --raw-output '.entries[0].lasttime')
lat=$(cat $aprsCall-myAPRS.json | jq --raw-output '.entries[0].lat')
lng=$(cat $aprsCall-myAPRS.json | jq --raw-output '.entries[0].lng')
last_time=$(cat $aprsCall-lastAPRS.json | jq --raw-output '.entries[0].time')
last_lasttime=$(cat $aprsCall-lastAPRS.json | jq --raw-output '.entries[0].lasttime')
last_lat=$(cat $aprsCall-lastAPRS.json | jq --raw-output '.entries[0].lat')
last_lng=$(cat $aprsCall-lastAPRS.json | jq --raw-output '.entries[0].lng')

# compare lasttime of current packet against lasttime of the last packet
if [ $last_time -eq $time ]
then
    # Notify that time is same and do no further processing
    echo "Packet time same as previous packet, Tweet not sent!"
else
    # compare lat and lng of current packet against lat and lng of the last packet
    if [ $lat = $last_lat ] && [ $lng = $last_lng ]
    then
        # Notify that location is same and do no further processing
        echo "Packet location is same as previous packet, Tweet not sent!"

    else
    # cURL get a landmark near me
    curl -s -X GET -H "Content-Type: *" --get "https://reverse.geocoder.ls.hereapi.com/6.2/reversegeocode.json" \
	--data-urlencode "prox=$lat,$lng,5000" --data-urlencode "mode=retrieveLandmarks" \
	--data-urlencode "apiKey=$hereApiKey" --data-urlencode "gen=8" > $aprsCall-myLndMrk.json

    # parse landmark JSON out and save landmark name into string variable
    landmark=$(cat $aprsCall-myLndMrk.json | jq '.Response.View[0].Result[0].Location.Name')

    # get city and state from location
    curl -s -X GET -H "Content-Type: *" --get "https://reverse.geocoder.ls.hereapi.com/6.2/reversegeocode.json" \
	--data-urlencode "prox=$lat,$lng,250" --data-urlencode "mode=retrieveAddresses" \
	--data-urlencode "maxresults=1" --data-urlencode "apiKey=$hereApiKey" \
	--data-urlencode "gen=8" > $aprsCall-myLocation.json

    landmark_state=$(cat $aprsCall-myLocation.json | jq --raw-output '.Response.View[0].Result[0].Location.Address.State')
    landmark_city=$(cat $aprsCall-myLocation.json | jq --raw-output '.Response.View[0].Result[0].Location.Address.City')
    landmark_city_noWhiteSpace=$(echo "${landmark_city// /_}")


    # neatly format time into something pretty
    dispTime=$(echo ${time:0:2}:${time:2:2}:${time:4:2})

    # parse additional string variables out of the current packet
    name=$(cat $aprsCall-myAPRS.json | jq --raw-output '.entries[0].name')
    status=$(cat $aprsCall-myAPRS.json | jq --raw-output '.entries[0].status')

    # concatonate string variables togeather to make up the location tweet
    tweet=$(echo $name is passing by $landmark in $landmark_city, $landmark_state with status $status 'http://tinyurl.com/dxja8qt #TweetAPRS #hamr')
    echo $tweet

    # send location tweet using twurl
    twurl -d "status=$tweet" /1.1/statuses/update.json > $aprsCall-lastTweet.json

    # parse tweet reply JSON and echo to console the time of tweet
    lastTweet=$(cat $aprsCall-lastTweet.json | jq --raw-output '.created_at')
    echo "Tweet sucessfully sent $lastTweet"

    # save current APRS data as last APRS (for checking time and posit against later
    cp "$aprsCall-myAPRS.json" "$aprsCall-lastAPRS.json"

    fi
fi
# wx tweet logic
touch -d '-1 hour' $aprsCall-last_WXcheck
if [ $aprsCall-last_WXcheck -nt $aprsCall-last_WXtweet ]
then

    # get weather from that location
    curl -G -s "https://api.openweathermap.org/data/2.5/weather" \
	--data-urlencode "lat=$lat" --data-urlencode "lon=$lng" --data-urlencode "units=imperial" --data-urlencode "APPID=$wx_ApiKey"> $aprsCall-myWX.json

    # parse weather strings into string variables
    weather=$(cat $aprsCall-myWX.json | jq --raw-output '.weather[0].main')
    temp=$(cat $aprsCall-myWX.json | jq --raw-output '.main.temp')
    windSpeed=$(cat $aprsCall-myWX.json | jq --raw-output '.wind.speed')
    windDir=$(cat $aprsCall-myWX.json | jq --raw-output '.wind.deg')
    baro_pres=$(cat $aprsCall-myWX.json | jq --raw-output '.main.pressure')

    # build WX tweet
    wxTweet=$(echo "Current WX at $aprsCall is $weather Temp $temp F, Wind $windSpeed MPH at $windDir Deg, Baro $baro_pres hPa #TweetAPRS #hamr")
    echo $wxTweet

    # send wx tweet
    twurl -d "status=$wxTweet" /1.1/statuses/update.json > $aprsCall-lastWXTweet.json

    # parse tweet reply JSON and echo to console the time of tweet
    lastWXTweet=$(cat $aprsCall-lastWXTweet.json | jq --raw-output '.created_at')
    echo "Tweet sucessfully sent $lastWXTweet"

    touch $aprsCall-last_wxtweet
else
    # no wx tweet
    echo "No WX Tweet Sent"
fi

# print end date/time of processing to console
endTime=$(date)
echo "TweetAPRS processing $aprsCall ended at $endTime"
echo \n
