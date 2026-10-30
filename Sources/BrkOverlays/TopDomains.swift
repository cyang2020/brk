import Foundation

/// Arc's "top domains" suggestion source (`TopDomainsCandidatesProvider`): the 458 sites of Arc 1.170's
/// `ARC_TopDomains.bundle/Contents/Resources/TopDomains.json`, in Arc's order (most visited first), one
/// "domain<TAB>site name" per line. Typing the start of a domain or a site name offers the site under the typed row.
enum TopDomains {
    struct Site: Equatable, Sendable {
        let domain: String
        let name: String
    }

    static let all: [Site] = table.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "\t", maxSplits: 1)
        return parts.count == 2 ? Site(domain: String(parts[0]), name: String(parts[1])) : nil
    }

    private static let table = """
google.com	Google
blogger.com	Blogger
youtube.com	YouTube
linkedin.com	LinkedIn
wordpress.org	WordPress
play.google.com	Google Play
apple.com	Apple
microsoft.com	Microsoft
docs.google.com	Google Docs
maps.google.com	Google Maps
wikipedia.org	Wikipedia
cloudflare.com	Cloudflare
whatsapp.com	WhatsApp
accounts.google.com	Google Accounts
mozilla.org	Mozilla
drive.google.com	Google Drive
europa.eu	European Union
adobe.com	Adobe
facebook.com	Facebook
amazon.com	Amazon
istockphoto.com	iStockphoto
t.me	Telegram
uol.com.br	UOL
github.com	GitHub
vimeo.com	Vimeo
gravatar.com	Gravatar
forbes.com	Forbes
dropbox.com	Dropbox
myspace.com	MySpace
cnn.com	CNN
medium.com	Medium
slideshare.net	SlideShare
sheets.google.com	Google Sheets
etsy.com	Etsy
dailymotion.com	Dailymotion
tiktok.com	TikTok
opera.com	Opera
msn.com	MSN
nytimes.com	The New York Times
wa.me	WhatsApp
nih.gov	National Institutes of Health (NIH)
bbc.co.uk	BBC
healthline.com	Healthline
brandbucket.com	BrandBucket
macys.com	Macys
realtor.com	Realtor
news.google.com	Google News
creativecommons.org	Creative Commons
wikimedia.org	Wikimedia
live.com	Outlook
craigslist.org	craigslist
imdb.com	IMDb
shopify.com	Shopify
line.me	LINE
yahoo.com	Yahoo
feedburner.com	FeedBurner
globo.com	Globo
paypal.com	PayPal
netvibes.com	Netvibes
bestbuy.com	Best Buy
who.int	World Health Organization (WHO)
theguardian.com	The Guardian
weebly.com	Weebly
mail.google.com	Gmail
jimdofree.com	Jimdo
afternic.com	Afternic
youronlinechoices.com	Your Online Choices
elpais.com	El País
picasaweb.google.com	Google Photos
fb.com	Facebook
t.co	Twitter
archive.org	Internet Archive
archiveofourown.org	Archive of Our Own
usps.com	USPS
telegraph.co.uk	The Telegraph
pinterest.com	Pinterest
thesun.co.uk	The Sun
same.energy	Same Energy
samsung.com	Samsung
webmd.com	WebMD
weather.com	The Weather Channel
weather.gov	National Weather Service
chase.com	Chase
allrecipes.com	Allrecipes
cpanel.net	cPanel
wsj.com	The Wall Street Journal
cvs.com	CVS
walgreens.com	Walgreens
independent.co.uk	The Independent
indeed.com	Indeed
gov.uk	GOV.UK
domainmarket.com	DomainMarket.com
networkadvertising.org	Network Advertising Initiative
cdc.gov	Centers for Disease Control and Prevention
hugedomains.com	HugeDomains.com
pixabay.com	Pixabay
twitter.com	Twitter
cbsnews.com	CBS News
buydomains.com	BuyDomains.com
huffingtonpost.com	HuffPost
nature.com	Nature
booking.com	Booking.com
w3.org	World Wide Web Consortium (W3C)
reuters.com	Reuters
godaddy.com	GoDaddy
ebay.com	eBay
wp.com	WordPress.com
change.org	Change.org
plesk.com	Plesk
namecheap.com	Namecheap
bbc.com	BBC
scribd.com	Scribd
time.com	TIME
usatoday.com	USA TODAY
issuu.com	Issuu
businessinsider.com	Business Insider
nasa.gov	NASA
amazon.co.uk	Amazon.co.uk
cnet.com	CNET
office.com	Microsoft Office
foxnews.com	Fox News
tinyurl.com	TinyURL
aliexpress.com	AliExpress
photos.google.com	Google Photos
bloomberg.com	Bloomberg
bing.com	Bing
indiatimes.com	India Times
huffpost.com	HuffPost
telegram.me	Telegram
myaccount.google.com	Google Account
goo.gl	Google URL Shortener
bit.ly	Bitly
planalto.gov.br	Planalto
mediafire.com	MediaFire
washingtonpost.com	The Washington Post
soundcloud.com	SoundCloud
shutterstock.com	Shutterstock
news.yahoo.com	Yahoo News
dailymail.co.uk	Daily Mail
instagram.com	Instagram
researchgate.net	ResearchGate
fandom.com	Fandom
t-mobile.com	T-Mobile
un.org	United Nations
livejournal.com	LiveJournal
calendar.google.com	Google Calendar
deezer.com	Deezer
playstation.com	PlayStation
berkeley.edu	UC Berkeley
duckduckgo.com	DuckDuckGo
ted.com	TED
abcnews.go.com	ABC News
smh.com.au	The Sydney Morning Herald
offset.com	Offset
aol.com	AOL
linktr.ee	Linktree
canada.ca	Government of Canada
lemonde.fr	Le Monde
yadi.sk	Yandex.Disk
ovh.com	OVHcloud
engadget.com	Engadget
psychologytoday.com	Psychology Today
sciencedirect.com	ScienceDirect
apache.org	The Apache Software Foundation
imageshack.us	ImageShack
mit.edu	MIT
ups.com	UPS
akamaihd.net	Akamai Technologies
wired.com	WIRED
clarin.com	Clarin
sky.com	Sky
pbs.org	PBS
yandex.com	Yandex
naver.com	Naver
zippyshare.com	Zippyshare
statista.com	Statista
espn.com	ESPN
alicdn.com	AliExpress
usablenet.com	UsableNet
whitehouse.gov	The White House
instructables.com	Instructables
translate.google.com	Google Translate
abc.es	ABC
alexa.com	Alexa
ft.com	Financial Times
elmundo.es	El Mundo
marca.com	Marca
cpanel.com	cPanel
gofundme.com	GoFundMe
cornell.edu	Cornell University
discord.gg	Discord
timeweb.ru	TimeWeb
finance.yahoo.com	Yahoo Finance
e-monsite.com	e-monsite
akamaized.net	Akamai
vice.com	VICE
redbull.com	Red Bull
unesco.org	UNESCO
rapidshare.com	RapidShare
prezi.com	Prezi
nikkei.com	Nikkei
springer.com	Springer
netlify.app	Netlify
search.yahoo.com	Yahoo Search
cambridge.org	Cambridge University Press
bp2.blogger.com	Blogger
ea.com	Electronic Arts
taringa.net	Taringa!
lavanguardia.com	La Vanguardia
ikea.com	IKEA
qq.com	QQ
zillow.com	Zillow
mozilla.com	Mozilla
nypost.com	New York Post
weibo.com	Weibo
canalblog.com	CanalBlog
photobucket.com	Photobucket
yelp.com	Yelp
gizmodo.com	Gizmodo
quora.com	Quora
sakura.ne.jp	SAKURA Internet
unsplash.com	Unsplash
detik.com	detikcom
android.com	Android
code.google.com	Google Developers
addtoany.com	AddToAny
pexels.com	Pexels
hindustantimes.com	Hindustan Times
nbcnews.com	NBC News
goodreads.com	Goodreads
wellsfargo.com	Wells Fargo
wikia.com	Fandom
dw.com	Deutsche Welle
yandex.ru	Yandex
theatlantic.com	The Atlantic
windows.net	Windows Azure
privacyshield.gov	Privacy Shield
discord.com	Discord
doi.org	DOI
wix.com	Wix
leparisien.fr	Le Parisien
books.google.com	Google Books
nydailynews.com	New York Daily News
mashable.com	Mashable
rtve.es	RTVE
insider.com	Insider
sciencedaily.com	ScienceDaily
bloglovin.com	Bloglovin'
urbandictionary.com	Urban Dictionary
rakuten.co.jp	Rakuten
hulu.com	Hulu
gnu.org	GNU Project
plos.org	PLOS
hubspot.com	HubSpot
cnil.fr	CNIL
sedo.com	Sedo
ziddu.com	Ziddu
steampowered.com	Steam
capitalone.com	Capital One
costco.com	Costco
rt.com	RT
icann.org	ICANN
kickstarter.com	Kickstarter
francetvinfo.fr	Franceinfo
npr.org	NPR
cointernet.com.co	.CO Internet
nationalgeographic.com	National Geographic
latimes.com	Los Angeles Times
outlook.com	Outlook
spotify.com	Spotify
ria.ru	RIA Novosti
cbc.ca	CBC
guardian.co.uk	The Guardian
cnbc.com	CNBC
ovhcloud.com	OVHcloud
tripadvisor.com	Tripadvisor
nginx.com	NGINX
oracle.com	Oracle
yahoo.co.jp	Yahoo! JAPAN
britannica.com	Encyclopedia Britannica
huawei.com	Huawei
buzzfeed.com	BuzzFeed
techcrunch.com	TechCrunch
zoom.us	Zoom
wiley.com	Wiley Online Library
home.pl	home.pl
homedepot.com	Home Depot
standard.co.uk	Evening Standard
newyorker.com	The New Yorker
secureserver.net	GoDaddy
hp.com	HP
ietf.org	IETF
sendspace.com	SendSpace
amazon.es	Amazon.es
oup.com	Oxford University Press
tmz.com	TMZ
bandcamp.com	Bandcamp
economist.com	The Economist
target.com	Target
webnode.page	Webnode
walmart.com	Walmart
surveymonkey.com	SurveyMonkey
ovh.net	OVH
abc.net.au	ABC News (Australia)
newsweek.com	Newsweek
zendesk.com	Zendesk
nginx.org	NGINX
dreamstime.com	Dreamstime
ca.gov	State of California
clickbank.net	ClickBank
nextdoor.com	Nextdoor
bankofamerica.com	Bank of America
hollywoodreporter.com	The Hollywood Reporter
academia.edu	Academia.edu
biglobe.ne.jp	BIGLOBE
liveinternet.ru	LiveInternet
sfgate.com	San Francisco Chronicle
roblox.com	Roblox
gmail.com	Gmail
ftc.gov	Federal Trade Commission
microsoft.com	Microsoft
fedex.com	Fedex
thenai.org	The NAI
twitch.tv	Twitch
wikipedia.org	Wikipedia
harvard.edu	Harvard University
rambler.ru	Rambler
radiofrance.fr	Radio France
stanford.edu	Stanford University
wikihow.com	wikiHow
ibm.com	IBM
eventbrite.com	Eventbrite
disney.com	Disney
addthis.com	AddThis
nicovideo.jp	Nico Nico Douga
welt.de	Die Welt
vkontakte.ru	VKontakte
kohls.com	Kohl's
skype.com	Skype
disqus.com	Disqus
loc.gov	Library of Congress
variety.com	Variety
thetimes.co.uk	The Times
php.net	PHP
amazonaws.com	Amazon Web Services (AWS)
netflix.com	Netflix
theverge.com	The Verge
about.com	About.com
themeforest.net	ThemeForest
picasa.google.com	Picasa
zdf.de	ZDF
lefigaro.fr	Le Figaro
usnews.com	U.S. News & World Report
mega.nz	MEGA
arxiv.org	arXiv
fb.me	Facebook
reg.ru	REG.RU
alibaba.com	Alibaba
namesilo.com	NameSilo
abc.com	ABC
thoughtco.com	ThoughtCo
billboard.com	Billboard
iso.org	ISO
canva.com	Canva
hbr.org	Harvard Business Review
ucoz.ru	uCoz
channel4.com	Channel 4
woocommerce.com	WooCommerce
imageshack.com	ImageShack
state.gov	U.S. Department of State
hm.com	H&M
pinterest.co.uk	Pinterest UK
example.com	Example Domain
digg.com	Digg
lg.com	LG
inc.com	Inc.
podcasts.google.com	Google Podcasts
namebright.com	NameBright
soratemplates.com	SoraTemplates
business.google.com	Google My Business
evernote.com	Evernote
fda.gov	U.S. Food and Drug Administration
ehow.com	eHow
ap.org	Associated Press
groups.yahoo.com	Yahoo Groups
repubblica.it	La Repubblica
bmj.com	BMJ
usgs.gov	U.S. Geological Survey
biblegateway.com	BibleGateway
uefa.com	UEFA
fedoraproject.org	Fedora Project
unicef.org	UNICEF
m.me	Facebook Messenger
amazon.ca	Amazon.ca
rollingstone.com	Rolling Stone
foursquare.com	Foursquare
last.fm	Last.fm
aftermarket.pl	AfterMarket.pl
imgur.com	Imgur
investopedia.com	Investopedia
fifa.com	FIFA
ebay.de	eBay Germany
trustpilot.com	Trustpilot
euronews.com	Euronews
eonline.com	E! Online
goal.com	Goal.com
apnews.com	AP News
sina.com.cn	Sina
ameba.jp	Ameba
upenn.edu	University of Pennsylvania
indiegogo.com	Indiegogo
utexas.edu	University of Texas at Austin
impress.co.jp	Impress Corporation
wordreference.com	WordReference
ign.com	IGN
answers.com	Answers.com
tabelog.com	Tabelog
boston.com	Boston.com
rbc.ru	RBC
zdnet.com	ZDNet
nba.com	NBA
scmp.com	South China Morning Post
mdpi.com	MDPI
digitaltrends.com	Digital Trends
depositfiles.com	DepositFiles
video.google.com	Google Video
scoop.it	Scoop.it
reddit.com	Reddit
stackoverflow.com	Stack Overflow
sec.gov	U.S. Securities and Exchange Commission
ucla.edu	University of California, Los Angeles
box.com	Box
flickr.com	Flickr
lenta.ru	Lenta.ru
xing.com	XING
usda.gov	U.S. Department of Agriculture
python.org	Python
blog.google	Google Blog
ox.ac.uk	University of Oxford
thedailybeast.com	The Daily Beast
amebaownd.com	Ameba Ownd
automattic.com	Automattic
att.com	AT&T
nps.gov	National Park Service
wiktionary.org	Wiktionary
joomla.org	Joomla!
people.com	People
stores.jp	Stores.jp
dribbble.com	Dribbble
go.co	Go.co
nifty.com	Nifty
vox.com	Vox
nhk.or.jp	NHK
esa.int	European Space Agency
lego.com	LEGO
gutenberg.org	Project Gutenberg
linear.app	Linear
notion.so	Notion
"""
}
