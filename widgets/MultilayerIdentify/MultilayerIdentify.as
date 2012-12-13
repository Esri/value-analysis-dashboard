/*
 | Version 10.1.1
 | Copyright 2010 Esri
 |
 | Licensed under the Apache License, Version 2.0 (the "License");
 | you may not use this file except in compliance with the License.
 | You may obtain a copy of the License at
 |
 |    http://www.apache.org/licenses/LICENSE-2.0
 |
 | Unless required by applicable law or agreed to in writing, software
 | distributed under the License is distributed on an "AS IS" BASIS,
 | WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 | See the License for the specific language governing permissions and
 | limitations under the License.
 */

// identifyLayers attribute (mkt)
package widgets.MultilayerIdentify
{
    import com.esri.ags.FeatureSet;
    import com.esri.ags.Graphic;
    import com.esri.ags.Map;
    import com.esri.ags.geometry.Extent;
    import com.esri.ags.geometry.MapPoint;
    import com.esri.ags.layers.ArcGISDynamicMapServiceLayer;
    import com.esri.ags.layers.ArcGISTiledMapServiceLayer;
    import com.esri.ags.layers.FeatureLayer;
    import com.esri.ags.layers.Layer;
    import com.esri.ags.layers.supportClasses.AttachmentInfo;
    import com.esri.ags.layers.supportClasses.LayerDetails;
    import com.esri.ags.layers.supportClasses.LayerInfo;
    import com.esri.ags.layers.supportClasses.Relationship;
    import com.esri.ags.tasks.IdentifyTask;
    import com.esri.ags.tasks.QueryTask;
    import com.esri.ags.tasks.supportClasses.IdentifyParameters;
    import com.esri.ags.tasks.supportClasses.Query;
    import com.esri.ags.tasks.supportClasses.RelationshipQuery;
    import com.esri.viewer.BaseWidget;

    import flash.display.Loader;
    import flash.events.Event;
    import flash.events.HTTPStatusEvent;
    import flash.events.IOErrorEvent;
    import flash.events.MouseEvent;
    import flash.events.SecurityErrorEvent;
    import flash.geom.Point;
    import flash.net.LocalConnection;
    import flash.net.URLRequest;
    import flash.system.ApplicationDomain;
    import flash.utils.Dictionary;

    import mx.collections.ArrayCollection;
    import mx.collections.ArrayList;
    import mx.containers.Panel;
    import mx.containers.ViewStack;
    import mx.controls.Image;
    import mx.controls.LinkButton;
    import mx.controls.SWFLoader;
    import mx.core.IFlexModuleFactory;
    import mx.core.IVisualElement;
    import mx.core.UIComponent;
    import mx.events.FlexEvent;
    import mx.events.ModuleEvent;
    import mx.graphics.IStroke;
    import mx.graphics.SolidColor;
    import mx.graphics.SolidColorStroke;
    import mx.modules.IModuleInfo;
    import mx.modules.ModuleLoader;
    import mx.modules.ModuleManager;
    import mx.rpc.AsyncResponder;

    import spark.components.BorderContainer;
    import spark.components.Button;
    import spark.components.HGroup;
    import spark.components.HSlider;
    import spark.components.Label;
    import spark.components.NavigatorContent;
    import spark.components.Panel;
    import spark.components.Scroller;
    import spark.components.TabBar;
    import spark.components.TileGroup;
    import spark.components.VGroup;
    import spark.components.supportClasses.GroupBase;
    import spark.core.IViewport;
    import spark.events.IndexChangeEvent;
    import spark.layouts.VerticalAlign;

    import widgets.HeaderController.HeaderGroup;
    import widgets.MultilayerIdentify.LayerAttributeFormatting;


    //================================================================================================//

    public class MultilayerIdentify
    {

        protected static var _instance:MultilayerIdentify = new MultilayerIdentify();

        // Returns singleton instance of class
        public static function get Instance():MultilayerIdentify
        {
            return _instance;
        }


        //--------------------------------------------------------------------------------------------//
        //---------- Launch parallel searches of the identifiable service layers

        protected var _map:Map;
        protected var _clickPoint:MapPoint;
        protected var _currentTimestamp:Number = 0;
        protected var _searches:ArrayList;
        protected var _numMapLayersQueried:Number;
        protected var _layerTabsHolder:ViewStack;
        protected var _layerTabsGraphics:Array;
        protected var _layerTabsInfoPackets:Array;
        private var _configFormats:Dictionary;
        protected var _reportLayersRemaining:Function;
        protected var _numberOfLayersWithResults:int = 0;
        protected var _assocItemsTabsHolder:ViewStack;
        protected var _validDomains:Array = [];

        public function set validDomains(validDomains:Array):void
        {
            _validDomains = validDomains;
        }

        // Begins the feature-search process
        public function launchNewSearch(map:Map, atPoint:MapPoint, toleranceRadiusPixels:Number,
            configFormats:Dictionary, reportLayersRemaining:Function=null):GroupBase
        {
            // ActionScript does not have block-level scope
            var infoPacket:MultilayerIdentifyInfo;
            var url:String;
            var layerFormat:Object;
            var sublayerName:String;

            // Searches are limited to a single map document
            _map = map;
            _clickPoint = atPoint;

            // Prepare for output
            _reportLayersRemaining = reportLayersRemaining;
            _layerTabsHolder = makeTabsHolder();
            var content:GroupBase = makeTabbedSet(_layerTabsHolder);

            _layerTabsGraphics = new Array();
            _layerTabsInfoPackets = new Array();
            _configFormats = configFormats;
            _numberOfLayersWithResults = 0;

            // Generate a timestamp for this series of queries (one or more queries per layer)
            _currentTimestamp = new Date().time;

            // Determine the set of services and map layers on each service to search. We can search
            // feature layers or some subset of the map layers that compose dynamic or tiled layers.
            _searches = new ArrayList();
            _numMapLayersQueried = 0;

            for(var iLayer:int = _map.layerIds.length - 1; 0 <= iLayer; --iLayer)
            {
                var layer:Layer = map.getLayer(map.layerIds[iLayer]);

                // Query map it if 1) is visible and 2) has a configFormat
                if(layer.visible)
                {
                    // Expand the click point into an extent since points never seem to get a hit
                    var clickBounds:Extent = pointToExtent(atPoint, layer, toleranceRadiusPixels);

                    if (layer is FeatureLayer)
                    {
                        layerFormat = _configFormats[layer.name];
                        if(null != layerFormat)
                        {
                            if("" == layerFormat.caption) layerFormat.caption = layer.name;
                            infoPacket =
                                new MultilayerIdentifyInfo(_currentTimestamp, layer, 0,
                                layer.name, (layer as FeatureLayer).url, layerFormat);
                            launchQuery(clickBounds, infoPacket);
                        }
                    }
                    else if (layer is ArcGISDynamicMapServiceLayer)
                    {
                        // Set up the search for each visible map layer in this service
                        var dynamicLayer:ArcGISDynamicMapServiceLayer =
                            layer as ArcGISDynamicMapServiceLayer;
                        url = dynamicLayer.url;
                        if("/" != url.charAt(url.length-1)) url += "/";
                        if(!dynamicLayer.visibleLayers)
                        {
                            dynamicLayer.visibleLayers = getDynamicVisibleLayers(dynamicLayer);
                        }
                        for each(var jLayer:int in dynamicLayer.visibleLayers)
                        {
                            layerFormat = _configFormats[layer.name + "\\" + jLayer.toString()];
                            if(null != layerFormat)
                            {
                                sublayerName = dynamicLayer.layerInfos[jLayer].name;
                                if("" == layerFormat.caption) layerFormat.caption = sublayerName;
                                infoPacket = new MultilayerIdentifyInfo(_currentTimestamp, layer,
                                    jLayer, sublayerName, url + jLayer, layerFormat);
                                launchQuery(clickBounds, infoPacket);
                            }
                        }
                    }
                    else if (layer is ArcGISTiledMapServiceLayer)
                    {
                        // Set up the search for each visible map layer in this service
                        var tiledLayer:ArcGISTiledMapServiceLayer = layer as ArcGISTiledMapServiceLayer;
                        url = tiledLayer.url;
                        if("/" != url.charAt(url.length-1)) url += "/";
                        for each(var kLayer:LayerInfo in tiledLayer.layerInfos)
                        {
                            layerFormat = _configFormats[kLayer.name];
                            if(kLayer.defaultVisibility && null != layerFormat)
                            {
                                if("" == layerFormat.caption) layerFormat.caption = kLayer.name;
                                infoPacket = new MultilayerIdentifyInfo(_currentTimestamp, layer,
                                    kLayer.layerId, kLayer.name, url + kLayer.layerId, layerFormat);
                                launchQuery(clickBounds, infoPacket);
                            }
                        }
                    }
                }
            }

            return content;
        }

        // Get the visible layers in a dynamic layer
        // Adapted from http://resources.arcgis.com/en/help/flex-api/samples/#/Dynamic_Map_Layers_on_off/01nq0000001t000000
        private function getDynamicVisibleLayers(mapLayer:ArcGISDynamicMapServiceLayer):ArrayCollection
        {
            var result:ArrayCollection = new ArrayCollection();

            for each (var layerInfo:LayerInfo in mapLayer.layerInfos)
            {
                if (layerInfo.defaultVisibility)
                {
                    result.addItem(layerInfo.layerId);
                }
            }

            return result;
        }

        // Provides access to search results' count of map layers with found features
        public function get numberOfLayersWithResults():int
        {
            return _numberOfLayersWithResults;
        }

        // Clears the current search
        public function clearCurrentSearch():void
        {
            // By zeroing the timestamp, any extant asynch searches will be orphaned; when their
            // results arrive, they will be discarded
            _currentTimestamp = 0;
            if(null != _layerTabsHolder) _layerTabsHolder.removeAllElements();
            _numberOfLayersWithResults = 0;
        }

        // Expands a point into an extent
        protected function pointToExtent(pt:MapPoint, containingLayer:Layer,
            tolerance:Number):Extent
        {
            if(null != containingLayer.map)
            {
                var screenPt:Point = containingLayer.map.toScreen(pt);

                var lowerLeftPixPt:Point = new Point(
                    screenPt.x - tolerance, screenPt.y - tolerance);
                var upperRightPixPt:Point = new Point(
                    screenPt.x + tolerance, screenPt.y + tolerance);

                var lowerLeftMapPt:MapPoint = containingLayer.map.toMap(lowerLeftPixPt);
                var upperRightMapPt:MapPoint = containingLayer.map.toMap(upperRightPixPt);

                return new Extent(
                    lowerLeftMapPt.x, lowerLeftMapPt.y, upperRightMapPt.x, upperRightMapPt.y,
                    pt.spatialReference);
            }
            else
            {
                return new Extent(pt.x, pt.y, pt.x, pt.y);
            }
        }

        // Launches a query for features for a specified map layer
        public function launchQuery(clickBounds:Extent, infoPacket:MultilayerIdentifyInfo):void
        {
            // Set up the search for this service
            var queryParams:Query = new Query();
            queryParams.returnGeometry = true;
            queryParams.geometry = clickBounds;
            queryParams.relationParam = com.esri.ags.tasks.supportClasses.Query.SPATIAL_REL_CONTAINS;
            queryParams.outFields = ["*"];

            // Launch the search
            var queryTask:QueryTask = new QueryTask();
            queryTask.useAMF = false;
            queryTask.url = infoPacket.queryUrl;
            queryTask.disableClientCaching = true;
            queryTask.execute(queryParams, new AsyncResponder(
                queryItemsHandler, queryFailureHandler, infoPacket));
            ++_numMapLayersQueried;
        }


        //--------------------------------------------------------------------------------------------//
        //---------- Extract Query's results

        // Handles the successful return from the query of a map layer by preparing the results for
        // the results displayer and invoking that displayer
        protected function queryItemsHandler(
            featureSet:FeatureSet, infoPacket:MultilayerIdentifyInfo):void
        {
            // Bundle up the results and send them to the search results displayer
            infoPacket.features = featureSet.features;
            infoPacket.fields = featureSet.fields;
            infoPacket.fieldAliases = featureSet.fieldAliases;
            searchResultsDisplayer(infoPacket);
        }

        // Handles the failure of a query of a map layer by recording any error information and
        // invoking the results displayer
        protected function queryFailureHandler(
            info:Object, infoPacket:MultilayerIdentifyInfo):void
        {
            // Save the error information and go on to the search results displayer
            // Failed searches continue onwards so that we can decrement remaining layers count
            infoPacket.info = info.toString();
            searchResultsDisplayer(infoPacket);
        }


        //--------------------------------------------------------------------------------------------//
        //---------- Coalesce the various asynchronous activities through a common landing point
        //---------- and report as much as we can each time we get here

        // Accepts the results of querying each map layer and displays successful finds
        protected function searchResultsDisplayer(infoPacket:MultilayerIdentifyInfo):void
        {
            // If either the search has already closed or these results are not for the current
            // search, we'll simply discard the results.
            if(0 == _currentTimestamp ||
                (null != infoPacket && _currentTimestamp != infoPacket.timestamp)) return;

            // Do we have something to show for this map layer?
            var numFeatures:Number = null == infoPacket.features ? 0 : infoPacket.features.length;
            if(0 < numFeatures)
            {
                addMapLayerToDisplay(infoPacket);
                ++_numberOfLayersWithResults;
            }

            // We completed a map layer search; decrement the count of remaining layers
            --_numMapLayersQueried;
            if(null != _reportLayersRemaining) _reportLayersRemaining(_numMapLayersQueried);
        }

        // Adds the results for a map layer to a tab in the widget'e display
        protected function addMapLayerToDisplay(infoPacket:MultilayerIdentifyInfo):void
        {
            // Create the tab page
            var tabNum:Number = _layerTabsHolder.length;
            var mapLayerPage:VGroup = new VGroup();

            // Add horizontal slidebar
            mapLayerPage.addElement(makeItemScroller(
                tabNum, infoPacket.features.length, updateFeatureSelection));

            // Add placeholder for feature display
            mapLayerPage.addElement(makeHGroup(tabNum));

            // Add placeholder for the associated items
            mapLayerPage.addElement(makeHGroup(tabNum));

            // Add the page & infoPacket to our lists & display of tabs
            _layerTabsGraphics = _layerTabsGraphics.concat(mapLayerPage);
            _layerTabsInfoPackets = _layerTabsInfoPackets.concat(infoPacket);
            _layerTabsHolder.addElement(
                addTab(infoPacket.layerFormat.caption,
                    addBorder(
                        addPadding(4, mapLayerPage)
                    )
                )
            );

            // Show the first feature of the map layer
            updateFeatureDisplay(tabNum, 0);
        }

        // Responds to a change in the feature selected by the widget's horizontal slider and its
        // accompanying arrows by triggering the display of the newly-selected feature's attributes
        protected function updateFeatureSelection(event:Event):void
        {
            // User the slider value (converted from 1-based to 0-based) to select the
            // feature to display
            var slider:HSlider = event.target as HSlider;
            var tabNum:Number = Number(slider.id);
            var iFeature:Number = slider.value - 1;
            updateFeatureDisplay(tabNum, iFeature);
        }

        // Displays the attributes of a map layer's feature and launches a query for items that are
        // related to and/or attached to the feature
        protected function updateFeatureDisplay(tabNum:Number, iFeature:Number):void
        {
            var vg:VGroup = _layerTabsGraphics[tabNum];

            // Create the report graphic & swap out the feature display block
            var infoPacket:MultilayerIdentifyInfo = _layerTabsInfoPackets[tabNum];
            var formatter:LayerAttributeFormatting =
                new LayerAttributeFormatting(infoPacket.layerFormat.format);
            var report:UIComponent = formatter.formatFields(infoPacket.features[iFeature],
                infoPacket.fields, infoPacket.fieldAliases);
            if(null == report) report = makeHGroup(tabNum);
            vg.removeElementAt(1);
            vg.addElementAt(report, 1);

            // Swap out the display for the associated items: attachments & related items
            vg.removeElementAt(2);
            var associatedItems:VGroup = new VGroup();
            if(null != infoPacket.mapLayerDetails)
            {
                var objectId:Number = getObjectId(infoPacket.features[iFeature],
                        infoPacket.fields, infoPacket.fieldAliases);

                if(null != infoPacket.mapLayerDetails.relationships
                    && 0 < infoPacket.mapLayerDetails.relationships.length)
                {
                    // Layer has related items--check if this feature is involved with
                    // one or more of them
                    for each(var relationship:Relationship in infoPacket.mapLayerDetails.relationships)
                    {
                        var query:RelationshipQuery = new RelationshipQuery();
                        query.objectIds = [objectId];
                        query.relationshipId = relationship.id;
                        query.outFields = ["*"];

                        var relationshipFormatName:String = infoPacket.mapLayerName
                            + "\\" + query.relationshipId.toString();
                        var layerFormat:Object = _configFormats[relationshipFormatName];
                        if(null == layerFormat)
                        {
                            var simpleformat:Object =
                            {
                                caption: relationship.name,
                                format: "*"
                            };
                            layerFormat = simpleformat;
                        }
                        else if("" == layerFormat.caption) layerFormat.caption = relationship.name;

                        var outputLoc:Object =
                        {
                            container: associatedItems,
                            layerFormat: layerFormat
                        };
                        (infoPacket.serviceLayer as FeatureLayer).queryRelatedFeatures(query,
                            new AsyncResponder(relationshipSuccessHandler, ignoreHandler, outputLoc));
                    }
                }
                if(infoPacket.mapLayerDetails.hasAttachments)
                {
                    // Layer has attachments--check if this feature has one or more of them
                    (infoPacket.serviceLayer as FeatureLayer).queryAttachmentInfos(objectId,
                        new AsyncResponder(attachmentSuccessHandler, ignoreHandler, associatedItems));
                }
            }
            vg.addElementAt(associatedItems, 2);
        }

        // Displays thumbnails and links for attachments found for a feature
        protected function attachmentSuccessHandler(results:Array, displayContainer:VGroup):void
        {
            // ActionScript does not have block-level scope
            if(null != results && 0 < results.length)
            {
                var itemsDisplay:VGroup = new VGroup();

                // Run through a list of urls adding them to the display
                for each(var info:AttachmentInfo in results)
                {
                    if(null != info.contentType)
                    {
                        if("image/png" == info.contentType ||
                            "image/jpeg" == info.contentType || "image/pjpeg" == info.contentType)
                        {
                            itemsDisplay.addElement(fullWidth(addBorder(
                                makeImageBlock(info.name, info.url, info.url))));
                        }
                        else if("application/pdf" == info.contentType)
                        {
                            // Give the icon elbow room as required by Adobe for the use of the PDF
                            // icon: "The Adobe PDF file icon must appear by itself, with a minimum
                            // spacing (the height of the icon) between each side of the icon and any
                            // other graphic or textual elements on your web page."
                            // http://www.adobe.com/misc/linking.html
                            // Side padding = icon height of 32
                            itemsDisplay.addElement(fullWidth(addBorder(makeImageBlock(
                                info.name, "assets/images/pdficon_large.gif", info.url, 32))));
                        }
                        else
                        {
                            itemsDisplay.addElement(fullWidth(addBorder(
                                makeImageBlock(info.name, "assets/images/document.png", info.url))));
                        }
                    }
                }

                // Create the tabbed set for associated items if it hasn't been done yet
                if(0 == displayContainer.numElements || null == _assocItemsTabsHolder)
                {
                    _assocItemsTabsHolder = makeTabsHolder();
                    var content:GroupBase = makeTabbedSet(_assocItemsTabsHolder);
                    displayContainer.addElement(content);
                }

                // Add the Attachments tab
                var attachmentsTitle:String = _configFormats["__attachmentsTitle"];
                _assocItemsTabsHolder.addElement(
                    addTab(attachmentsTitle + " (" + itemsDisplay.numElements.toString() + ")",
                        addBorder(
                            addPadding(4, itemsDisplay)
                        )
                    )
                );
            }
        }

        // Makes a visual block consisting of an image thumbnail and a text label that may also be
        // a link
        protected function makeImageBlock(caption:String, imageUrl:String,
            linkUrl:String, sidePadding:Number=0):HGroup
        {
            var hg:HGroup = new HGroup();
            hg.verticalAlign = "middle";
            hg.paddingLeft = hg.paddingTop = hg.paddingRight = hg.paddingBottom = 5;
            hg.minHeight = 32;

            if(0 < sidePadding)
            {
                var pad1:BorderContainer = new BorderContainer();
                pad1.width = sidePadding - 6;  // for gap between HGroup elements
                pad1.height = 32;
                pad1.setStyle("borderVisible", false);
                pad1.backgroundFill = new SolidColor(0xffffff, 0);
                hg.addElement(pad1);
            }

            var img:Image = new Image();
            img.addEventListener(Event.COMPLETE, function(event:Event):void {
                // Now that the image is loaded, constrain it to a box 100x100 while preserving
                // the aspect ratio. maxWidth & maxHeight leave reserved blank areas:
                // "In this example, you do not specify a square area for the resized image. Flex
                // maintains the aspect ratio of an image by default; therefore, Flex sizes the image
                // to 150 by 150 pixels, the largest possible image that maintains the aspect ratio and
                // conforms to the size constraints. The other 50 by 150 pixels remain empty. However,
                // the <mx:Image> tag reserves the empty pixels and makes them unavailable to other
                // controls and layout elements." We don't want the empty area, so we manage the
                // sizing and aspect ratio ourselves.
                // http://livedocs.adobe.com/flex/3/html/help.html?content=controls_16.html
                var loadedImage:Image = Image(event.target);
                var aspectRatio:Number = loadedImage.contentWidth / loadedImage.contentHeight;
                if(1 <= aspectRatio)
                {
                    var constrainedWidth:Number = Math.min(loadedImage.contentWidth, 100);
                    loadedImage.width = constrainedWidth;
                    loadedImage.height = constrainedWidth / aspectRatio;
                }
                else
                {
                    var constrainedHeight:Number = Math.min(loadedImage.contentHeight, 100);
                    loadedImage.height = constrainedHeight;
                    loadedImage.width = constrainedHeight * aspectRatio;
                }
            });
            img.addEventListener(IOErrorEvent.IO_ERROR, function(event:IOErrorEvent):void {
                (event.currentTarget as Image).source = "assets/images/document.png";
            });
            img.addEventListener(
                SecurityErrorEvent.SECURITY_ERROR, function(event:SecurityErrorEvent):void {
                (event.currentTarget as Image).source = "assets/images/document.png";
            });
            // http://blog.flexexamples.com/2007/11/04/detecting-whether-an-image-loaded-successfully-in-flex/
            img.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(event:HTTPStatusEvent):void {
                if(200 != event.status && 0 != event.status)
                {
                    (event.currentTarget as Image).source = "assets/images/document.png";
                }
            });
            img.source = imageUrl;
            hg.addElement(img);

            if(0 < sidePadding)
            {
                var pad2:BorderContainer = new BorderContainer();
                pad2.width = sidePadding - 6;  // for gap between HGroup elements
                pad2.height = 32;
                pad2.setStyle("borderVisible", false);
                pad2.backgroundFill = new SolidColor(0xffffff, 0);
                hg.addElement(pad2);
            }

            var label:UIComponent = makeLink(caption, linkUrl);
            hg.addElement(label);

            return hg;
        }

        // Creates a caption that's also a link if the url of the link points to the same domain as
        // the widget and if it's either the http or https protocol
        protected function makeLink(caption:String, linkUrl:String):UIComponent
        {
            var link:UIComponent = null;

            // Validate the URL to make sure that it begins with http:// and that it's from our domain
            // From "Important Security Note" under Adobe's ActionScript 3.0 Reference for navigateToURL
            // http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/
            //   flash/net/package.html#navigateToURL%28%29
            if(checkProtocol(linkUrl))
            {
                link = new LinkButton();
                (link as LinkButton).label = caption;
                (link as LinkButton).setStyle("textDecoration", "underline");
                (link as LinkButton).addEventListener(MouseEvent.CLICK,
                    function(event:MouseEvent):void {
                    flash.net.navigateToURL(new URLRequest(linkUrl), "_blank");
                });
            }
            else
            {
                link = new Label();
                (link as Label).text = caption;
            }

            return link;
        }

        // AS3 Regular expression pattern match for URLs that start with http:// and https:// plus
        // your domain name.
        // http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/
        //   flash/net/package.html#navigateToURL%28%29
        protected function checkProtocol(flashVarURL:String):Boolean
        {
            // Get the domain name for the SWF if it is not known at compile time.
            // If the domain is known at compile time, then the following two lines can be replaced
            // with a hard coded string.
            var my_lc:LocalConnection = new LocalConnection();
            var domainName:String = my_lc.domain;

            // Build the RegEx to test the URL.
            // This RegEx assumes that there is at least one "/" after the
            // domain. http://www.mysite.com will not match.
            var pattern:RegExp = new RegExp("^http[s]?\:\\/\\/([^\\/]+)\\/");
            var result:Object = pattern.exec(flashVarURL);
            if (result == null || flashVarURL.length >= 4096) {
                return (false);
            }
            if (result[1] == domainName || 0 <= _validDomains.indexOf(result[1]))
            {
                return (true);
            }
            return (false);
        }

        // Displays formatted content for relationships found for a feature
        protected function relationshipSuccessHandler(results:Object, outputLoc:Object):void
        {
            if(null != results)
            {
                var itemsDisplay:VGroup = new VGroup();
                var layerFormat:Object = outputLoc.layerFormat;
                for each(var fs:FeatureSet in results)
                {
                    // Run through a list of related Graphics adding them to the display
                    for each(var info:Graphic in fs.features)
                    {
                        var formatter:LayerAttributeFormatting =
                            new LayerAttributeFormatting(layerFormat.format);
                        var report:UIComponent =
                            formatter.formatFields(info, fs.fields, fs.fieldAliases);
                        if(null != report)
                        {
                            itemsDisplay.addElement(fullWidth(addBorder(addPadding(5, report))));
                        }
                    }
                }

                if(0 < itemsDisplay.numElements)
                {
                    // Create the tabbed set for associated items if it hasn't been done yet
                    var displayContainer:VGroup = VGroup(outputLoc.container);
                    if(0 == displayContainer.numElements || null == _assocItemsTabsHolder)
                    {
                        _assocItemsTabsHolder = makeTabsHolder();
                        var content:GroupBase = makeTabbedSet(_assocItemsTabsHolder);
                        displayContainer.addElement(content);
                    }

                    // Add the Attachments tab
                    _assocItemsTabsHolder.addElement(
                        addTab(layerFormat.caption + " (" + itemsDisplay.numElements.toString() + ")",
                            addBorder(
                                addPadding(4, itemsDisplay)
                            )
                        )
                    );
                }
            }
        }

        // Handles query results by doing nothing
        protected function ignoreHandler(result:Object, data:Object=null):void
        {
        }

        // Retrieves the OBJECTID of a feature
        protected function getObjectId(feature:Graphic, fields:Array, fieldAliases:Object):Number
        {
            // Find the OBJECTID field
            for(var name:String in feature.attributes)
            {
                if("OBJECTID" == name)
                {
                    // If it has a value, we're set
                    if(null != feature.attributes[name])
                    {
                        return Number(feature.attributes[name]);
                    }
                    // Otherwise, see if we can get a value via its alias
                    else
                    {
                        var alias:String = null;
                        if(null != fieldAliases)
                        {
                            alias = fieldAliases[name];
                        }
                        else if(null != fields)
                        {
                            for(var iField:int = 0; iField < fields.length; ++iField)
                            {
                                if(name == fields[iField].name)
                                {
                                    alias = fields[iField].alias;
                                    break;
                                }
                            }
                        }
                        if(null != feature.attributes[alias])
                        {
                            return Number(feature.attributes[alias]);
                        }
                    }
                }
            }
            return Number.NaN;
        }


        //--------------------------------------------------------------------------------------------//
        //---------- Provide a framework to show the collection of viewers

        // Creates a component that contains the specified item and surrounds it with padding
        protected function addPadding(paddingPix:Number, item:UIComponent):UIComponent
        {
            // Pad the item
            var bufferedItem:VGroup = new VGroup();
            bufferedItem.paddingLeft = paddingPix;
            bufferedItem.paddingTop = paddingPix;
            bufferedItem.paddingRight = paddingPix;
            bufferedItem.paddingBottom = paddingPix;
            bufferedItem.addElement(item);
            item.percentWidth = 100;

            return bufferedItem;
        }

        // Creates a component that contains the specified item and surrounds it with a border
        protected function addBorder(item:UIComponent):UIComponent
        {
            // Surround the item with a border
            var borderedItem:BorderContainer = new BorderContainer();
            borderedItem.backgroundFill = new SolidColor(0xffffff, 0.10);
            borderedItem.borderStroke = new SolidColorStroke(0x000000, 1, 0.5);
            borderedItem.minHeight = 20;  // pixels
            borderedItem.setStyle("cornerRadius", 5);
            borderedItem.addElement(item);

            return borderedItem;
        }

        // Sets a component to expand to the full width of its container
        protected function fullWidth(item:UIComponent):UIComponent
        {
            item.percentWidth = 100;
            return item;
        }

        // Creates a component that contains the specified item as a tabbed item
        protected function addTab(label:String, item:UIComponent):UIComponent
        {
            // Put the item in the context of a tab
            var tabbedItem:NavigatorContent = new NavigatorContent();
            tabbedItem.label = label;
            tabbedItem.addElement(item);
            item.percentWidth = 100;

            return tabbedItem;
        }

        // Creates a container for a set of tabbed items
        protected function makeTabsHolder():ViewStack
        {
            return new ViewStack();
        }

        // Creates a tab bar for the supplied tabbed-item container
        protected function makeTabbedSet(tabsHolder:ViewStack):GroupBase
        {
            var tabBar:TabBar = new TabBar();
            tabBar.dataProvider = tabsHolder;

            var tabbedSet:VGroup = new VGroup();
            tabbedSet.gap = 0;
            tabbedSet.addElement(tabBar);
            tabbedSet.addElement(tabsHolder);
            tabsHolder.percentWidth = 100;

            return tabbedSet;
        }

        // Creates a block that consists of a horizontal slider and affiliated selection-change arrows
        protected function makeItemScroller(id:Number, itemCount:Number,
            updateFunction:Function):GroupBase
        {
            var hs:HSlider = new HSlider();
            hs.id = id.toString();
            hs.dataTipPrecision = 0;
            hs.minimum = 1;
            hs.maximum = itemCount;
            hs.addEventListener(spark.events.IndexChangeEvent.CHANGE, updateFunction);

            var leftArrow:Image = new Image();
            leftArrow.id = id.toString();
            leftArrow.source = "assets/images/w_left.png";
            leftArrow.addEventListener(MouseEvent.CLICK, function(e:Event):void
            {
                if(hs.minimum < hs.value)
                {
                    --hs.value;
                    // Create an event; not done automatically because it's not from user interaction
                    hs.dispatchEvent(new IndexChangeEvent(spark.events.IndexChangeEvent.CHANGE,
                        false, false, hs.value + 1, hs.value));
                }
            });

            var minTxt:Label = new Label();
            minTxt.text = hs.minimum.toString();

            var maxTxt:Label = new Label();
            maxTxt.text = hs.maximum.toString();

            var rightArrow:Image = new Image();
            rightArrow.id = id.toString();
            rightArrow.source = "assets/images/w_right.png";
            rightArrow.addEventListener(MouseEvent.CLICK, function(e:Event):void
            {
                if(hs.maximum > hs.value)
                {
                    ++hs.value;
                    // Create an event; not done automatically because it's not from user interaction
                    hs.dispatchEvent(new IndexChangeEvent(spark.events.IndexChangeEvent.CHANGE,
                        false, false, hs.value - 1, hs.value));
                }
            });

            var hg:HGroup = makeHGroup(id);
            hg.addElement(leftArrow);
            hg.addElement(minTxt);
            hg.addElement(hs);
            hg.addElement(maxTxt);
            hg.addElement(rightArrow);
            hg.visible = 1 < itemCount;
            return hg;
        }

        // Creates an HGroup whose items are aligned via their middles
        protected function makeHGroup(id:Number):HGroup
        {
            var hg:HGroup = new HGroup();
            hg.verticalAlign = spark.layouts.VerticalAlign.MIDDLE;
            hg.id = id.toString();
            return hg;
        }
    }
}