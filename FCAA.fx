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
uniform float Subpix < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_tooltip = "Amount of sub-pixel aliasing removal. Higher values makes the image softer/blurrier";
> = 0.75;
uniform float EdgeThreshold < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Edge Detection Threshold";
	ui_tooltip = "The minimum amount of local contrast required to apply algorithm.";
> = 0.166;
uniform float EdgeThresholdMin < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
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

#define texLuma(tex, pos) tex2Dlod(LumaBuffer, float4(pos, 0, 0)).r
#define texLumaOff(tex, pos, off) tex2Dlod(LumaBuffer, float4(pos, 0, 0), off).r

float4 FCAA(sampler tex,float2 texcoord) {
	float2 posM = texcoord;
	float lumaM = texLuma(tex, posM);
	float lumaS = texLumaOff(tex, posM, int2( 0, 1));
	float lumaE = texLumaOff(tex, posM, int2( 1, 0));
	float lumaN = texLumaOff(tex, posM, int2( 0,-1));
	float lumaW = texLumaOff(tex, posM, int2(-1, 0));
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
		discard;
/*--------------------------------------------------------------------------*/
	float lumaNW = texLumaOff(tex, posM, int2(-1,-1));
	float lumaSE = texLumaOff(tex, posM, int2( 1, 1));
	float lumaNE = texLumaOff(tex, posM, int2( 1,-1));
	float lumaSW = texLumaOff(tex, posM, int2(-1, 1));
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
/*--------------------------------------------------------------------------*/
	float lengthSign = BUFFER_PIXEL_SIZE.x;
	bool horzSpan = edgeHorz >= edgeVert;
/*--------------------------------------------------------------------------*/
	if(!horzSpan) lumaN = lumaW;
	if(!horzSpan) lumaS = lumaE;
	if( horzSpan) lengthSign = BUFFER_PIXEL_SIZE.y;
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
	float2 posP = posN;
	posN += offNP * 0.5;
	posP -= offNP * 0.5;
/*--------------------------------------------------------------------------*/
	if(!pairN) lumaNN = lumaSS;
	float gradientScaled = gradient * 1.0/4.0;
	float lumaMM = lumaM - lumaNN * 0.5;
	bool lumaMLTZero = lumaMM < 0.0;
/*--------------------------------------------------------------------------*/
	float lumaEndP;
	float lumaEndN;
	bool doneN = false;
	bool doneP = false;
	for(int i = 0; (i < MaxSearchSteps) && (!doneN || !doneP); ++i) {
		if(!doneN) posN -= offNP * 2.0;
		if(!doneN) lumaEndN = texLuma(tex, posN);
		if(!doneN) lumaEndN -= lumaNN * 0.5;
		doneN = abs(lumaEndN) >= gradientScaled;
		if(!doneP) posP += offNP * 2.0;
		if(!doneP) lumaEndP = texLuma(tex, posP);
		if(!doneP) lumaEndP -= lumaNN * 0.5;
		doneP = abs(lumaEndP) >= gradientScaled;
	}
/*--------------------------------------------------------------------------*/
	float adjN = abs(abs(lumaEndN) - gradientScaled) >= 0.25 ? -0.5 : 0.5;
	float adjP = abs(abs(lumaEndP) - gradientScaled) >= 0.25 ? -0.5 : 0.5;
	posN -= offNP * adjN;
	posP += offNP * adjP;
	float dstN = posM.x - posN.x;
	float dstP = posP.x - posM.x;
/*--------------------------------------------------------------------------*/
	if(!horzSpan) dstN = posM.y - posN.y;
	if(!horzSpan) dstP = posP.y - posM.y;
	bool goodSpanN = (lumaEndN < 0.0) != lumaMLTZero;
	float spanLength = (dstP + dstN);
	bool goodSpanP = (lumaEndP < 0.0) != lumaMLTZero;
	float spanLengthRcp = 1.0/spanLength;
/*--------------------------------------------------------------------------*/
	bool directionN = dstN < dstP;
	float dst = min(dstN, dstP);
	bool goodSpan = directionN ? goodSpanN : goodSpanP;
	float pixelOffsetSubpix;
	[flatten]
	if (spanLength >= dot(5.0, offNP))
	{
/*--------------------------------------------------------------------------*/
		float pixelOffset = (dst * (-spanLengthRcp)) + 0.5;
		float2 posB = directionN ? posN : posP;
		if (!horzSpan) posB.x -= lengthSign;
		if ( horzSpan) posB.y -= lengthSign;
/*--------------------------------------------------------------------------*/
		float lumaB = texLuma(tex, posB);
		goodSpan = goodSpan && abs(lumaB - lumaNN * 0.5) < gradientScaled * 1.5;
		pixelOffsetSubpix = goodSpan ? pixelOffset : 0.0;
	}
	else
	{
/*--------------------------------------------------------------------------*/
		float subpixRcpRange = 1.0/range;
		float subpixNSWE = lumaNS + lumaWE;
		float subpixNWSWNESE = lumaNWSW + lumaNESE;
		float subpixA = subpixNSWE * 2.0 + subpixNWSWNESE;
/*--------------------------------------------------------------------------*/
		float subpixB = (subpixA * (1.0/12.0)) - lumaM;
		float subpixC = saturate(abs(subpixB) * subpixRcpRange);
		float subpixD = ((-2.0)*subpixC) + 3.0;
		float subpixE = subpixC * subpixC;
/*--------------------------------------------------------------------------*/
		float subpixF = subpixD * subpixE;
		float subpixG = subpixF * subpixF;
		pixelOffsetSubpix = subpixG * Subpix;
	}
	if(!horzSpan) posM.x += pixelOffsetSubpix * lengthSign;
	if( horzSpan) posM.y += pixelOffsetSubpix * lengthSign;

	return float4(tex2Dlod(tex, float4(posM, 0, 0)).rgb, lumaM);
}

float4 CXAAPS(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
	return FCAA(BackBuffer, texcoord);
}

float LumaPS(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
	return (dot(tex2Dlod(BackBuffer, float4(texcoord, 0, 0)).rgb, float3(0.299, 0.587, 0.114)));
}

// Vertex shader generating a triangle covering the entire screen
void PostProcessVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD) {
	texcoord.x = (id == 2) ? 2.0 : 0.0;
	texcoord.y = (id == 1) ? 2.0 : 0.0;
	position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

technique FCAA  <
	ui_tooltip = "It is a modified version of Timothy Lottes' PC FXAA algorithm "
	"designed to preserve overall sharpness of the input image "
	"while being resource-efficient and providing a visually pleasing aliased result.\n"
	"by jfouquart";>
{
	pass {
		VertexShader = PostProcessVS;
		PixelShader = LumaPS;
		RenderTarget = LumaTex;
	}
	pass {
		VertexShader = PostProcessVS;
		PixelShader = CXAAPS;
	}
}

}
