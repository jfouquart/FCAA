//
//------------------------------------------------------------------------------------------------------
// based on NVIDIA FXAA 3.11 by TIMOTHY LOTTES,
// COPYRIGHT (C) 2010, 2011 NVIDIA CORPORATION.
//
//------------------------------------------------------------------------------------------------------
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
// OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//------------------------------------------------------------------------------------------------------
// based on LG Electronics AXAA by Jae-Ho Nah, Sunho Ki, Yeongkyu Lim, Jinhong Park, and Chulho Shin
// for the rangeMid early-exit criterion ( see https://nahjaeho.github.io/papers/SIG2016/SIG2016_AXAA.pdf )
//
//------------------------------------------------------------------------------------------------------

#include "ReShadeUI.fxh"
#include "ReShade.fxh"

namespace FCAA {

/*============================================================================
		SETTINGS
============================================================================*/
uniform float EdgeThreshold < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 0.5;
	ui_label = "Edge Detection Threshold";
	ui_tooltip = "The minimum amount of local contrast required to apply algorithm.";
> = 0.166;
uniform float EdgeThresholdMin < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 0.1;
	ui_label = "Darkness Threshold";
	ui_tooltip = "Pixels darker than this are not processed in order to increase performance.";
> = 0.0833;
uniform int MaxSearchSteps  < __UNIFORM_SLIDER_INT1
	ui_min = 4; ui_max = 32;
	ui_label = "Max Search Steps";
	ui_tooltip = "Determines the maximum search radius for aliased edges.";
> = 16;

// Samplers
texture2D LumaTex<pooled = true;>
{
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
	Format = R8;
};
sampler2D LumaBuffer
{
	Texture = LumaTex;
	MinFilter = Linear; MagFilter = Linear;
};

sampler2D BackBuffer
{
	Texture = ReShade::BackBufferTex;
	MinFilter = Linear; MagFilter = Linear;
};

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define texLuma(pos) tex2Dlod(LumaBuffer, float4(pos, 0, 0)).r
#define texLumaOff(pos, off) tex2Dlod(LumaBuffer, float4(pos, 0, 0), off).r

int SpanProp(float2 posM) {
	float lumaM = texLuma(posM);
	float lumaS = texLumaOff(posM, int2( 0, 1));
	float lumaE = texLumaOff(posM, int2( 1, 0));
	float lumaN = texLumaOff(posM, int2( 0,-1));
	float lumaW = texLumaOff(posM, int2(-1, 0));
/*--------------------------------------------------------------------------*/
	float rangeMax = max(max(lumaN, lumaW), max(lumaE, max(lumaS, lumaM)));
	float rangeMin = min(min(lumaN, lumaW), min(lumaE, min(lumaS, lumaM)));
	float rangeMaxScaled = rangeMax * EdgeThreshold;
	float range = rangeMax - rangeMin;
/*--------------------------------------------------------------------------*/
	float rangeMaxClamped = max(EdgeThresholdMin, rangeMaxScaled);
	float rangeMid = 0.5 * (rangeMin + rangeMax);
	float alpha = 0.1 * range;
	bool midRangePix = abs(lumaM - rangeMid) <= alpha;
	bool earlyExit = range < rangeMaxClamped;
/*--------------------------------------------------------------------------*/
	if(midRangePix || earlyExit)
		return 0;
/*--------------------------------------------------------------------------*/
	float lumaNW = texLumaOff(posM, int2(-1,-1));
	float lumaSE = texLumaOff(posM, int2( 1, 1));
	float lumaNE = texLumaOff(posM, int2( 1,-1));
	float lumaSW = texLumaOff(posM, int2(-1, 1));
/*--------------------------------------------------------------------------*/
	float lumaNS = lumaN + lumaS;
	float lumaWE = lumaW + lumaE;
	float lumaNESE = lumaNE + lumaSE;
	float lumaNWNE = lumaNW + lumaNE;
/*--------------------------------------------------------------------------*/
	float lumaNWSW = lumaNW + lumaSW;
	float lumaSWSE = lumaSW + lumaSE;
	float edgeHorz =
		abs(lumaNWSW - 2.0 * lumaW) +
		abs(lumaNS   - 2.0 * lumaM) * 2.0 +
		abs(lumaNESE - 2.0 * lumaE);
	float edgeVert =
		abs(lumaSWSE - 2.0 * lumaS) +
		abs(lumaWE   - 2.0 * lumaM) * 2.0 +
		abs(lumaNWNE - 2.0 * lumaN);

	return (edgeHorz >= edgeVert) ? 1 : 2;
}

float3 FCAA(float2 posM) {
	float lumaM = texLuma(posM);
	int spanPropM = SpanProp(posM);
/*--------------------------------------------------------------------------*/
#if 0
	if (spanPropM == 0) return lumaM.xxx;
	else return float3(0,1,0);
#else
	if (spanPropM == 0)
		discard;
#endif
/*--------------------------------------------------------------------------*/
	bool horzSpan = spanPropM == 1;
	float lengthSign = BUFFER_PIXEL_SIZE.y;
	float lumaN = texLumaOff(posM, int2( 0,-1));
	float lumaS = texLumaOff(posM, int2( 0, 1));
	if(!horzSpan) lengthSign = BUFFER_PIXEL_SIZE.x;
	if(!horzSpan) lumaN = texLumaOff(posM, int2(-1, 0));
	if(!horzSpan) lumaS = texLumaOff(posM, int2( 1, 0));
/*--------------------------------------------------------------------------*/
	float gradientN = lumaN - lumaM;
	float gradientS = lumaS - lumaM;
	float lumaNN = lumaN + lumaM;
	float lumaSS = lumaS + lumaM;
	bool pairN = abs(gradientN) >= abs(gradientS);
	float gradient = max(abs(gradientN), abs(gradientS));
	if(pairN) lengthSign = -lengthSign;
/*--------------------------------------------------------------------------*/
	float2 posN = posM;
	float2 offNP;
	offNP.x = (!horzSpan) ? 0.0 : BUFFER_PIXEL_SIZE.x;
	offNP.y = ( horzSpan) ? 0.0 : BUFFER_PIXEL_SIZE.y;
	if(!horzSpan) posN.x += lengthSign * 0.5;
	if( horzSpan) posN.y += lengthSign * 0.5;
/*--------------------------------------------------------------------------*/
	if(!pairN) lumaNN = lumaSS;
	float lumaMN = lumaNN * 0.5;
	float gradientScaled = gradient * 0.25;
	float2 posP = posN;
	posN -= offNP;
	posP += offNP;
/*--------------------------------------------------------------------------*/
	float lumaEndN = texLuma(posN) - lumaMN;
	float lumaEndP = texLuma(posP) - lumaMN;
	bool doneN = abs(lumaEndN) >= gradientScaled;
	bool doneP = abs(lumaEndP) >= gradientScaled;
	if(!doneN) posN += offNP * 0.5;
	if(!doneP) posP -= offNP * 0.5;
/*--------------------------------------------------------------------------*/
	for(int i = 1; (i < MaxSearchSteps) && (!doneN || !doneP); ++i) {
		if(!doneN) posN -= offNP * 2.0;
		if(!doneN) lumaEndN = texLuma(posN);
		if(!doneN) lumaEndN -= lumaMN;
		doneN = abs(lumaEndN) >= gradientScaled;
		if(!doneP) posP += offNP * 2.0;
		if(!doneP) lumaEndP = texLuma(posP);
		if(!doneP) lumaEndP -= lumaMN;
		doneP = abs(lumaEndP) >= gradientScaled;
	}
/*--------------------------------------------------------------------------*/
	float dstN = posM.x - posN.x;
	float dstP = posP.x - posM.x;
	if(!horzSpan) dstN = posM.y - posN.y;
	if(!horzSpan) dstP = posP.y - posM.y;
	float lumaMM = lumaM - lumaMN;
	bool lumaMLTZero = lumaMM < 0.0;
/*--------------------------------------------------------------------------*/
	bool directionN = dstN < dstP;
	float dst = min(dstN, dstP);
	bool goodSpanN = (lumaEndN < 0.0) != lumaMLTZero;
	bool goodSpanP = (lumaEndP < 0.0) != lumaMLTZero;
	bool goodSpan = directionN ? goodSpanN : goodSpanP;
/*--------------------------------------------------------------------------*/
	float2 posB = posP;
	float off = max(offNP.x,offNP.y);
	float offB = (dst / off > 1.75) ? 0.5 : 0.0;
	float lumaEnd = lumaEndP;
	if(directionN) posB = posN;
	if(directionN) offB = -offB;
	if(directionN) lumaEnd = lumaEndN;
/*--------------------------------------------------------------------------*/
    bool beyondSpan = abs(lumaEnd) > gradient * 0.5;
	if(beyondSpan) offB = -offB;
	if(!horzSpan) posB.x -= lengthSign * 0.5;
	if( horzSpan) posB.y -= lengthSign * 0.5;
	posB += offB * offNP;
	if(goodSpan) goodSpan = (SpanProp(posB) == spanPropM);
/*--------------------------------------------------------------------------*/
	float spanLength = (dstP + dstN + off);
	float pixelOffset = (-dst / spanLength) + 0.5;
/*--------------------------------------------------------------------------*/
	float pixelOffsetGood = goodSpan ? pixelOffset : 0.0;
	if(!horzSpan) posM.x += pixelOffsetGood * lengthSign;
	if( horzSpan) posM.y += pixelOffsetGood * lengthSign;

	return tex2Dlod(BackBuffer, float4(posM, 0, 0)).rgb;
}

float3 FCAAPS(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
	return FCAA(texcoord);
}

float LumaPS(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
	float3 c = tex2Dlod(BackBuffer, float4(texcoord, 0, 0)).rgb;
	return dot(c, float3(0.299, 0.587, 0.114));
}

// Vertex shader generating a triangle covering the entire screen
void PostProcessVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD) {
	texcoord.x = (id == 2) ? 2.0 : 0.0;
	texcoord.y = (id == 1) ? 2.0 : 0.0;
	position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

technique FCAA <
	ui_label = "FCAA";
	ui_tooltip =
	"                      Fast Conservative Anti-Aliasing                       \n"
	"____________________________________________________________________________\n"
	"\n"
	"It is a modified version of Timothy Lottes' PC FXAA algorithm designed to   \n"
	"preserve overall sharpness of the input image while being resource-efficient\n"
	"and providing a visually pleasing aliased result.                           \n"
	"\n"
	"by jfouquart";
> {
	pass {
		VertexShader = PostProcessVS;
		PixelShader = LumaPS;
		RenderTarget = LumaTex;
	}
	pass {
		VertexShader = PostProcessVS;
		PixelShader = FCAAPS;
	}
}

}
